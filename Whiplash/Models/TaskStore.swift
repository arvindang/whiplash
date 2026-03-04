import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    var tasks: [WhiplashTask] = []
    private let fileURL: URL
    private var fileWatcher: FileWatcher?

    /// Ephemeral state: frontmost app info captured before popover opens
    @ObservationIgnored var lastFrontmostPID: Int32?
    @ObservationIgnored var lastFrontmostBundleID: String?

    static let shared = TaskStore()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        fileURL = home.appendingPathComponent(".whiplash.json")
        loadTasks()
        fileWatcher = FileWatcher(url: fileURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadTasks()
            }
        }
    }

    var activeTasks: [WhiplashTask] {
        tasks.filter { $0.status != .done }
    }

    var activeOrWaitingCount: Int {
        tasks.count { $0.status == .active || $0.status == .waiting }
    }

    var activeCount: Int {
        activeTasks.count
    }

    func addTask(title: String, context: String, projectPath: String? = nil, gitBranch: String? = nil) {
        let task = WhiplashTask(title: title, context: context, projectPath: projectPath, gitBranch: gitBranch)
        tasks.append(task)
        saveTasks()
    }

    func updateStatus(_ id: UUID, status: WhiplashTask.TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
        tasks[index].updatedAt = Date()
        saveTasks()
    }

    /// Pause toggle removed from GUI; kept for CLI compatibility.
    func togglePause(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let current = tasks[index].status
        tasks[index].status = current == .paused ? .active : .paused
        tasks[index].manuallyCompleted = false
        tasks[index].updatedAt = Date()
        saveTasks()
    }

    func markDone(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .done
        tasks[index].manuallyCompleted = true
        tasks[index].updatedAt = Date()
        saveTasks()
    }

    func dismissTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    func clearAll() {
        tasks.removeAll()
        saveTasks()
    }

    func reconcileAISessions(_ sessions: [AISession]) {
        var changed = false

        let sessionMap = Dictionary(sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { _, last in last })

        // 1. Create tasks for running sessions without existing tasks
        for session in sessions where session.isProcessRunning {
            if !tasks.contains(where: { $0.sessionId == session.sessionId }) {
                let title = session.projectName
                let task = WhiplashTask(
                    title: title,
                    context: session.tool.contextName,
                    isAutoDetected: true,
                    sessionId: session.sessionId,
                    projectPath: session.projectPath,
                    gitBranch: session.gitBranch,
                    pid: session.pid,
                    terminalApp: session.terminalApp
                )
                tasks.append(task)
                changed = true
            }
        }

        // 2. Update existing tasks / 3. Mark done
        for i in tasks.indices {
            guard tasks[i].isAutoDetected, let sid = tasks[i].sessionId else { continue }

            if let session = sessionMap[sid] {
                // Update metadata
                if tasks[i].pid != session.pid {
                    tasks[i].pid = session.pid
                    changed = true
                }
                if tasks[i].gitBranch != session.gitBranch {
                    tasks[i].gitBranch = session.gitBranch
                    changed = true
                }
                if tasks[i].terminalApp != session.terminalApp {
                    tasks[i].terminalApp = session.terminalApp
                    changed = true
                }

                if session.isProcessRunning {
                    // Revive if was done but session is running again (unless manually completed)
                    if tasks[i].status == .done && !tasks[i].manuallyCompleted {
                        tasks[i].status = .active
                        tasks[i].updatedAt = Date()
                        changed = true
                    }

                    // Transition active ↔ waiting based on session state
                    if session.isWaitingForInput && tasks[i].status == .active {
                        tasks[i].status = .waiting
                        tasks[i].updatedAt = Date()
                        changed = true
                    } else if !session.isWaitingForInput && tasks[i].status == .waiting {
                        tasks[i].status = .active
                        tasks[i].updatedAt = Date()
                        changed = true
                    }
                } else {
                    // Process not running — mark done
                    if tasks[i].status != .done {
                        tasks[i].status = .done
                        tasks[i].manuallyCompleted = false
                        tasks[i].updatedAt = Date()
                        changed = true
                    }
                }
            } else {
                // Session not in scan results at all — mark done
                if tasks[i].status != .done {
                    tasks[i].status = .done
                    tasks[i].manuallyCompleted = false
                    tasks[i].updatedAt = Date()
                    changed = true
                }
            }
        }

        if changed { saveTasks() }
    }

    func loadTasks() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            tasks = try decoder.decode([WhiplashTask].self, from: data)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    func saveTasks() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }
}
