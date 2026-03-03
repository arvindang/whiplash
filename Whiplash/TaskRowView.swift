import SwiftUI

enum TaskRowAction {
    case markDone
    case togglePause
    case dismiss
}

struct TaskRowView: View {
    let task: WhiplashTask
    let onAction: (TaskRowAction) -> Void

    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            // Swipe left background — mark done (green)
            if offset < 0 {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(.trailing, 16)
                }
            }

            // Swipe right background — pause/resume (orange)
            if offset > 0 {
                HStack {
                    Image(systemName: task.status == .paused ? "play.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(.orange)
                        .padding(.leading, 16)
                    Spacer()
                }
            }

            // Main row content
            rowContent
                .offset(x: offset)
                .gesture(swipeGesture)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .opacity(task.status == .done ? 0.5 : 1.0)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    contextPill
                    if let branch = task.gitBranch, branch != "HEAD", !branch.isEmpty {
                        Text(branch)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(TimeFormatter.relativeTime(from: task.updatedAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if task.isAutoDetected {
                Button(action: { onAction(.dismiss) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial) // opaque background hides swipe indicators
    }

    private var contextPill: some View {
        Text(task.context)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(contextColor))
    }

    private var statusColor: Color {
        switch task.status {
        case .active: .green
        case .paused: .orange
        case .done: .gray
        }
    }

    private var contextColor: Color {
        switch task.context.lowercased() {
        case let c where c.contains("iterm"): .blue
        case let c where c.contains("claude"): .purple
        case let c where c.contains("cowork"): .orange
        case let c where c.contains("terminal"): .blue
        case let c where c.contains("xcode"): .cyan
        default: .gray
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                offset = value.translation.width
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.3)) {
                    if value.translation.width < -60 {
                        onAction(.markDone)
                    } else if value.translation.width > 60 {
                        onAction(.togglePause)
                    }
                    offset = 0
                }
            }
    }
}
