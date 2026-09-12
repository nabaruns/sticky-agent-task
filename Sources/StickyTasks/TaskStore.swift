import Foundation

/// One unit of work shown on a sticky note. Maps to one Claude prompt/turn.
struct AgentTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var session: String
    var cwd: String?
    var status: String            // "running" | "done"
    var startedAt: Double
    var doneAt: Double?

    var isDone: Bool { status == "done" }
}

/// Shared location every session writes to and the panel reads from.
enum StorePaths {
    static var dir: URL {
        FileManager.default.homeDirectoryForUser.appendingPathComponent(".claude", isDirectory: true)
    }
    static var file: URL {
        dir.appendingPathComponent("sticky-tasks.json")
    }
    static var lock: URL {
        dir.appendingPathComponent("sticky-tasks.lock")
    }
}

extension FileManager {
    var homeDirectoryForUser: URL {
        // homeDirectoryForCurrentUser can point at a sandbox container; resolve the real home.
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return homeDirectoryForCurrentUser
    }
}

/// Cross-process persistence for the task list. Uses an flock'd lock file so
/// concurrent Claude sessions never corrupt the JSON, plus atomic replace on write.
enum TaskStoreIO {
    /// Keep this many notes total (done stay until pushed out by newer ones).
    static let maxNotes = 30
    /// A "running" task with no stop event after this long is assumed abandoned.
    static let staleRunning: TimeInterval = 60 * 60 * 6

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: StorePaths.dir, withIntermediateDirectories: true)
    }

    static func read() -> [AgentTask] {
        guard let data = try? Data(contentsOf: StorePaths.file) else { return [] }
        return (try? JSONDecoder().decode([AgentTask].self, from: data)) ?? []
    }

    /// Take the lock, mutate the list, prune, and write it back atomically.
    static func mutate(_ body: (inout [AgentTask]) -> Void) {
        ensureDir()
        let lockFD = open(StorePaths.lock.path, O_CREAT | O_RDWR, 0o644)
        if lockFD >= 0 { flock(lockFD, LOCK_EX) }
        defer {
            if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) }
        }

        var tasks = read()
        body(&tasks)
        prune(&tasks)

        if let data = try? JSONEncoder().encode(tasks) {
            let tmp = StorePaths.file.appendingPathExtension("tmp-\(getpid())")
            do {
                try data.write(to: tmp, options: .atomic)
                _ = try? FileManager.default.replaceItemAt(StorePaths.file, withItemAt: tmp)
            } catch {
                try? data.write(to: StorePaths.file, options: .atomic)
                try? FileManager.default.removeItem(at: tmp)
            }
        }
    }

    private static func prune(_ tasks: inout [AgentTask]) {
        let now = Date().timeIntervalSince1970
        // Only drop running tasks that were clearly abandoned; done tasks persist.
        tasks.removeAll { t in !t.isDone && now - t.startedAt > staleRunning }
        // Keep the newest N so the board doesn't grow without bound.
        if tasks.count > maxNotes {
            tasks = Array(tasks.suffix(maxNotes))
        }
    }
}
