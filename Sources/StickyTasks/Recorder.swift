import Foundation

/// Hook-side entry point. Reads a Claude Code hook payload from stdin and updates
/// the shared task file. Invoked as `StickyTasks record --event start|stop`.
enum Recorder {
    static func run(event: String) {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]

        let session = (json["session_id"] as? String) ?? "unknown"
        let cwd = json["cwd"] as? String
        let now = Date().timeIntervalSince1970

        switch event {
        case "start":
            let prompt = (json["prompt"] as? String) ?? "Working…"
            let title = summarize(prompt)
            TaskStoreIO.mutate { tasks in
                // One note per session: reuse it (flip back to running) if present.
                if let idx = tasks.firstIndex(where: { $0.session == session }) {
                    tasks[idx].title = title
                    tasks[idx].cwd = cwd
                    tasks[idx].status = "running"
                    tasks[idx].startedAt = now
                    tasks[idx].doneAt = nil
                } else {
                    tasks.append(AgentTask(
                        id: UUID().uuidString,
                        title: title,
                        session: session,
                        cwd: cwd,
                        status: "running",
                        startedAt: now,
                        doneAt: nil))
                }
            }

        case "stop":
            TaskStoreIO.mutate { tasks in
                // Finish this session's note.
                if let idx = tasks.firstIndex(where: { $0.session == session }) {
                    tasks[idx].status = "done"
                    tasks[idx].doneAt = now
                }
            }

        default:
            break
        }
        // Hooks must exit 0 so they never block or alter Claude's flow.
        exit(0)
    }

    /// Turn a raw prompt into a short, single-line note title.
    private static func summarize(_ prompt: String) -> String {
        let collapsed = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSentence = collapsed.split(whereSeparator: { $0 == "." || $0 == "?" || $0 == "!" }).first.map(String.init) ?? collapsed
        let base = firstSentence.isEmpty ? collapsed : firstSentence
        if base.count <= 64 { return base.isEmpty ? "Working…" : base }
        let idx = base.index(base.startIndex, offsetBy: 63)
        return String(base[..<idx]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
