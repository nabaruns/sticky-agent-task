import SwiftUI
import Combine

/// Drives the panel: polls the shared file and exposes every note. Done notes
/// stay put — seeing what finished vs what's still running is the whole point.
/// The list is bounded by count (see TaskStoreIO), not by time.
@MainActor
final class BoardModel: ObservableObject {
    @Published private(set) var tasks: [AgentTask] = []

    private var timer: Timer?
    private var lastMTime: TimeInterval = 0

    func start() {
        reload(force: true)
        // Watch the file and keep "running for Ns" subtitles ticking.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        reload(force: false)
        objectWillChange.send()   // refresh elapsed-time subtitles
    }

    private func reload(force: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: StorePaths.file.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        guard force || mtime != lastMTime else { return }
        lastMTime = mtime
        let loaded = TaskStoreIO.read()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            tasks = loaded
        }
    }

    /// Oldest at top, newest at the bottom.
    var ordered: [AgentTask] {
        tasks.sorted { $0.startedAt < $1.startedAt }
    }

    var runningCount: Int { tasks.filter { !$0.isDone }.count }

    func clearAll() {
        TaskStoreIO.mutate { $0.removeAll() }
        reload(force: true)
    }

    /// Dismiss one note (used by the × on finished notes).
    func remove(id: String) {
        TaskStoreIO.mutate { $0.removeAll { $0.id == id } }
        reload(force: true)
    }
}
