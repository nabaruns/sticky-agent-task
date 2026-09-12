import AppKit
import SwiftUI
import Combine

/// Hosting view that registers a click even when its panel isn't the key window,
/// so the first tap on the tab pins it open instead of just activating.
final class FirstMouseHostingView<T: View>: NSHostingView<T> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shared open/pinned state between the controller (which resizes the panel) and
/// the SwiftUI view (which renders tab vs notes).
@MainActor
final class PanelState: ObservableObject {
    @Published var expanded = false     // notes showing (via hover or pin)
    @Published var pinned = false       // click-locked open until clicked again
}

/// Owns the floating panel and the menu-bar item. The panel lives at the right
/// edge, vertically centered. At rest it's a small tab (a "tip") that blocks
/// nothing. Hovering peeks the notes; clicking the tab pins them open.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private let model = BoardModel()
    private let state = PanelState()

    private var isHovering = false
    private var collapseWork: DispatchWorkItem?

    // Geometry
    private let tabWidth: CGFloat = 34
    private let tabHeight: CGFloat = 150
    private let panelWidth: CGFloat = 320
    private let maxExpandedHeight: CGFloat = 560

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        buildPanel()
        buildStatusItem()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false        // needs hover + click on the tab
        panel.hidesOnDeactivate = false

        let root = BoardView(
            model: model,
            state: state,
            onHoverChange: { [weak self] in self?.setHovering($0) },
            onTabClick: { [weak self] in self?.togglePinned() },
            onClose: { [weak self] in self?.close() })
        let host = FirstMouseHostingView(rootView: root)
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        applyFrame(animate: false)
        panel.orderFrontRegardless()
    }

    /// Right edge, vertically centered. Height grows with the note count up to a cap.
    private func frame(expanded: Bool) -> NSRect {
        let vf = (panel?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        if expanded {
            let want = CGFloat(max(1, model.ordered.count)) * 66 + 28
            let h = min(max(140, want), min(maxExpandedHeight, vf.height - 40))
            return NSRect(x: vf.maxX - panelWidth, y: vf.midY - h / 2,
                          width: panelWidth, height: h)
        }
        return NSRect(x: vf.maxX - tabWidth, y: vf.midY - tabHeight / 2,
                      width: tabWidth, height: tabHeight)
    }

    private func applyFrame(animate: Bool) {
        panel?.setFrame(frame(expanded: state.expanded), display: true, animate: animate)
    }

    private func setExpanded(_ open: Bool) {
        guard state.expanded != open else { return }
        state.expanded = open
        applyFrame(animate: false)
    }

    /// Hover peeks; a pinned panel ignores hover-out and stays open.
    private func setHovering(_ hovering: Bool) {
        isHovering = hovering
        collapseWork?.cancel()
        if hovering {
            setExpanded(true)
        } else if !state.pinned {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.state.pinned, !self.isHovering else { return }
                self.setExpanded(false)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    /// Click the tab: lock it open, or if already open, unpin (and collapse unless hovered).
    private func togglePinned() {
        state.pinned.toggle()
        collapseWork?.cancel()
        if state.pinned {
            setExpanded(true)
        } else if !isHovering {
            setExpanded(false)
        }
    }

    private func close() {
        state.pinned = false
        collapseWork?.cancel()
        setExpanded(false)
    }

    @objc private func screenChanged() { applyFrame(animate: false) }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🗒️"
        let menu = NSMenu()
        menu.addItem(withTitle: "Sticky Agent Tasks", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Add demo note", action: #selector(demo), keyEquivalent: "d").target = self
        menu.addItem(withTitle: "Clear all notes", action: #selector(clear), keyEquivalent: "k").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func clear() { model.clearAll(); applyFrame(animate: false) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func demo() {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        TaskStoreIO.mutate { tasks in
            tasks.append(AgentTask(id: id, title: "Demo task: refactor the parser",
                                   session: "demo", cwd: FileManager.default.currentDirectoryPath,
                                   status: "running", startedAt: now, doneAt: nil))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            TaskStoreIO.mutate { tasks in
                if let i = tasks.firstIndex(where: { $0.id == id }) {
                    tasks[i].status = "done"
                    tasks[i].doneAt = Date().timeIntervalSince1970
                }
            }
        }
    }
}
