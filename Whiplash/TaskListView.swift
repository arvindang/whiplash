import SwiftUI

struct TaskListView: View {
    @Bindable var store: TaskStore
    let sessionScanner: SessionScanner
    let summaryProvider: SummaryProvider
    @State private var isAddingTask = false
    @State private var detectedFolderName: String?
    @State private var detectedProjectPath: String?
    @State private var detectedGitBranch: String?
    @State private var detectedContext: String?
    @State private var expandedTaskId: UUID?
    @State private var summaries: [UUID: String] = [:]
    @State private var loadingSummaryId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            taskList
            Divider()
            footer
        }
        .frame(width: 320, height: 400)
        .background(.ultraThinMaterial)
        .onChange(of: isAddingTask) { _, newValue in
            if newValue {
                startProjectDetection()
            } else {
                clearDetectedInfo()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Whiplash")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            Spacer()
            if store.activeCount > 0 {
                Text("\(store.activeCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.blue))
            }
            Button(action: { isAddingTask.toggle() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isAddingTask {
                    AddTaskView(
                        initialTitle: detectedFolderName,
                        initialContext: detectedContext,
                        detectedProjectPath: detectedProjectPath,
                        detectedGitBranch: detectedGitBranch
                    ) { title, context, projectPath, gitBranch in
                        store.addTask(title: title, context: context, projectPath: projectPath, gitBranch: gitBranch)
                        isAddingTask = false
                    } onCancel: {
                        isAddingTask = false
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    Divider().padding(.horizontal, 10)
                }

                if store.visibleTasks.isEmpty && !isAddingTask {
                    emptyState
                } else {
                    ForEach(store.visibleTasks) { task in
                        TaskRowView(
                            task: task,
                            isExpanded: expandedTaskId == task.id,
                            summary: summaries[task.id],
                            isLoadingSummary: loadingSummaryId == task.id,
                            onAction: { action in
                                handleAction(action, for: task.id)
                            },
                            onTap: {
                                toggleExpansion(for: task)
                            }
                        )
                        Divider().padding(.horizontal, 10)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No active tasks")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Click + to add one")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") {
                store.clearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func handleAction(_ action: TaskRowAction, for id: UUID) {
        switch action {
        case .markDone:
            store.markDone(id)
        case .togglePause:
            store.togglePause(id)
        case .dismiss:
            store.dismissTask(id)
        }
    }

    // MARK: - Expansion & Summary

    private func toggleExpansion(for task: WhiplashTask) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedTaskId == task.id {
                expandedTaskId = nil
                return
            }
            expandedTaskId = task.id
        }

        // Fetch summary if not cached
        guard summaries[task.id] == nil else { return }
        guard task.sessionId != nil else { return }

        loadingSummaryId = task.id
        Task {
            let result = await summaryProvider.summary(for: task)
            loadingSummaryId = nil
            if let result {
                summaries[task.id] = result
            }
        }
    }

    // MARK: - Project Detection

    private func startProjectDetection() {
        guard let pid = store.lastFrontmostPID else { return }
        let bundleID = store.lastFrontmostBundleID
        let isTerminal = Self.isTerminalApp(bundleID)

        // Auto-select context based on frontmost app
        detectedContext = Self.contextForBundleID(bundleID)

        Task {
            if let info = await sessionScanner.detectProjectInfo(forPID: pid, isTerminal: isTerminal) {
                detectedFolderName = info.folderName
                detectedProjectPath = info.path
                detectedGitBranch = info.gitBranch
            }
        }
    }

    private func clearDetectedInfo() {
        detectedFolderName = nil
        detectedProjectPath = nil
        detectedGitBranch = nil
        detectedContext = nil
    }

    private static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "com.github.alacritty",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "org.wezfurlong.wezterm",
    ]

    private static func isTerminalApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return terminalBundleIDs.contains(bundleID)
    }

    private static func contextForBundleID(_ bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        switch bundleID {
        case "com.googlecode.iterm2": return "iTerm"
        case "com.apple.Terminal": return "Terminal"
        case "com.apple.dt.Xcode": return "Xcode"
        case "com.mitchellh.ghostty": return "Ghostty"
        case "dev.warp.Warp-Stable": return "Warp"
        case "net.kovidgoyal.kitty": return "kitty"
        case "com.github.alacritty": return "Alacritty"
        case "org.wezfurlong.wezterm": return "WezTerm"
        default: return nil
        }
    }
}
