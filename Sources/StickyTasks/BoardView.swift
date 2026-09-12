import SwiftUI

/// The right-edge overlay. Collapsed it's a small tab; hovering peeks the notes,
/// clicking the tab pins them open. The parent panel resizes to match.
struct BoardView: View {
    @ObservedObject var model: BoardModel
    @ObservedObject var state: PanelState
    let onHoverChange: (Bool) -> Void
    let onTabClick: () -> Void
    let onClose: () -> Void

    private var count: Int { model.ordered.count }
    private var running: Int { model.runningCount }
    private var hasFreshDone: Bool {
        let now = Date().timeIntervalSince1970
        return model.ordered.contains { $0.isDone && now - ($0.doneAt ?? 0) < 4 }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.clear                        // hover target across the whole panel
            if state.expanded {
                panelBody
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TabHandle(count: count, running: running, celebrate: hasFreshDone)
                    .contentShape(Rectangle())
                    .onTapGesture { onTabClick() }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: state.expanded)
    }

    private var panelBody: some View {
        VStack(spacing: 6) {
            header
            notesList
        }
        .padding(.trailing, 12)
        .padding(.leading, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(running > 0 ? "\(running) running" : "all done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Image(systemName: state.pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.pinned ? Color(red: 1.0, green: 0.85, blue: 0.3) : .white.opacity(0.7))
                .padding(5)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Rectangle())
                .onTapGesture { state.pinned ? onClose() : onTabClick() }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }

    private var notesList: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer(minLength: 0)
                    ForEach(model.ordered) { task in
                        StickyNoteView(task: task, onDismiss: { model.remove(id: task.id) })
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height)   // center when few, scroll when many
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The resting "tip": a rounded tab hugging the right edge. Amber when something
/// is running; nudges when a task has just finished.
private struct TabHandle: View {
    let count: Int
    let running: Int
    let celebrate: Bool
    @State private var pulse = false
    @State private var nudge = false

    private var tint: Color {
        running > 0 ? Color(red: 0.85, green: 0.55, blue: 0.05) : Color(red: 0.16, green: 0.62, blue: 0.30)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.compact.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            if running > 0 {
                Circle().fill(.white).frame(width: 5, height: 5)
                    .opacity(pulse ? 0.3 : 1.0)
            }
        }
        .frame(width: 30, height: 116)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 15, style: .continuous)
                .fill(tint.opacity(0.95))
                .shadow(color: .black.opacity(0.22), radius: 6, x: -2, y: 2))
        .offset(x: nudge ? -6 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: celebrate) { _, now in
            guard now else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { nudge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { nudge = false }
            }
        }
    }
}

/// A single note. Running is compact and softly pulsing; done "rises" — taller,
/// brighter, lifted with a pop and a stronger shadow — so it feels finished.
struct StickyNoteView: View {
    let task: AgentTask
    var onDismiss: () -> Void = {}
    @State private var pulse = false
    @State private var appeared = false

    private var done: Bool { task.isDone }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusGlyph
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: done ? .semibold : .medium))
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(done ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.black.opacity(0.42))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, done ? 14 : 9)
        .frame(width: 272, alignment: .leading)
        .background(noteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if done {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.85)))
                    .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .offset(x: 6, y: -6)
            }
        }
        .shadow(color: .black.opacity(done ? 0.28 : 0.14),
                radius: done ? 16 : 7, x: 0, y: done ? 9 : 4)
        .scaleEffect(appeared ? 1.0 : 0.85)
        .offset(y: done ? -2 : 0)
        .rotationEffect(.degrees(done ? 0 : -0.6))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.55), value: done)
    }

    private var statusGlyph: some View {
        ZStack {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white, Color(red: 0.16, green: 0.62, blue: 0.30))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .fill(Color(red: 0.85, green: 0.55, blue: 0.05))
                    .frame(width: 9, height: 9)
                    .opacity(pulse ? 0.35 : 1.0)
                    .padding(4)
            }
        }
        .frame(width: 20, height: 20)
    }

    private var subtitle: String {
        if done, let done = task.doneAt {
            let secs = max(0, done - task.startedAt)
            return "done in \(format(secs))" + folderSuffix
        }
        let secs = Date().timeIntervalSince1970 - task.startedAt
        return "running \(format(secs))" + folderSuffix
    }

    private var folderSuffix: String {
        guard let cwd = task.cwd else { return "" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "" : "  ·  \(name)"
    }

    private func format(_ s: Double) -> String {
        if s < 60 { return "\(Int(s.rounded()))s" }
        let m = Int(s) / 60, r = Int(s) % 60
        return "\(m)m \(r)s"
    }

    @ViewBuilder private var noteBackground: some View {
        if done {
            LinearGradient(
                colors: [Color(red: 0.79, green: 0.94, blue: 0.79),
                         Color(red: 0.66, green: 0.89, blue: 0.68)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.95, blue: 0.70),
                         Color(red: 0.99, green: 0.90, blue: 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
