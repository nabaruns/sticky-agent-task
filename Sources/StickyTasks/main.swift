import AppKit

// Two modes in one binary:
//   StickyTasks record --event start|stop   → hook recorder (reads stdin, updates file)
//   StickyTasks                             → the floating sticky-note panel
let args = CommandLine.arguments

if args.count >= 2, args[1] == "record" {
    var event = "start"
    if let i = args.firstIndex(of: "--event"), i + 1 < args.count {
        event = args[i + 1]
    }
    Recorder.run(event: event)
} else {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.run()
}
