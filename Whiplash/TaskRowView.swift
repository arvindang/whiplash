import SwiftUI

enum TaskRowAction {
    case dismiss          // X button: immediate removal
    case completedDismiss // Checkmark: slide-off removal (done tasks only)
}

struct TaskRowView: View {
    let task: WhiplashTask
    let isExpanded: Bool
    let summary: String?
    let isLoadingSummary: Bool
    let onAction: (TaskRowAction) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            if isExpanded {
                expandedContent
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .opacity(task.status == .done ? 0.5 : 1.0)
    .animation(.easeInOut(duration: 0.3), value: task.status)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isLoadingSummary {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        } else if let summary {
            Text(summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        } else {
            Text(noSummaryMessage)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    private var noSummaryMessage: String {
        if task.sessionId == nil {
            return "Manual task"
        }
        let ctx = task.context.lowercased()
        if ctx.contains("gemini") { return "Summary not available for Gemini sessions" }
        if ctx.contains("codex") { return "Summary not available for Codex sessions" }
        return "No session data"
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text(TimeFormatter.relativeTime(from: task.updatedAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    contextPill
                    if let terminal = task.terminalApp {
                        terminalPill(terminal)
                    }
                    if let branch = task.gitBranch, branch != "HEAD", !branch.isEmpty {
                        Text(branch)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if task.status == .done {
                Button(action: { onAction(.completedDismiss) }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }

            Button(action: { onAction(.dismiss) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
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
        case .waiting: .yellow
        }
    }

    private func terminalPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(terminalColor(name)))
    }

    private func terminalColor(_ name: String) -> Color {
        switch name {
        case "iTerm2":    return .blue
        case "Terminal":  return .blue
        case "Ghostty":   return .indigo
        case "Warp":      return .teal
        case "kitty":     return .pink
        case "Alacritty": return .orange
        case "WezTerm":   return .brown
        case "tmux":      return .green
        default:          return .gray
        }
    }

    private var contextColor: Color {
        switch task.context.lowercased() {
        case let c where c.contains("iterm"): .blue
        case let c where c.contains("claude"): .purple
        case let c where c.contains("codex"): .green
        case let c where c.contains("gemini"): .mint
        case let c where c.contains("cowork"): .orange
        case let c where c.contains("terminal"): .blue
        case let c where c.contains("xcode"): .cyan
        default: .gray
        }
    }
}
