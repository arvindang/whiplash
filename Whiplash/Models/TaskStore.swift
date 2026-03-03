import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    var tasks: [WhiplashTask] = []
    private let fileURL: URL
    private var fileWatcher: FileWatcher?

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

    var activeCount: Int {
        activeTasks.count
    }

    /// Tasks marked done more than 5 minutes ago are hidden
    var visibleTasks: [WhiplashTask] {
        let cutoff = Date().addingTimeInterval(-300)
        return tasks.filter { task in
            if task.status == .done {
                return task.updatedAt > cutoff
            }
            return true
        }
    }

    func addTask(title: String, context: String) {
        let task = WhiplashTask(title: title, context: context)
        tasks.append(task)
        saveTasks()
    }

    func updateStatus(_ id: UUID, status: WhiplashTask.TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
        tasks[index].updatedAt = Date()
        saveTasks()
    }

    func togglePause(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let current = tasks[index].status
        tasks[index].status = current == .paused ? .active : .paused
        tasks[index].updatedAt = Date()
        saveTasks()
    }

    func markDone(_ id: UUID) {
        updateStatus(id, status: .done)
    }

    func dismissTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    func reconcileClaudeSessions(_ sessions: [ClaudeSession]) {
        var changed = false

        let sessionMap = Dictionary(sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { _, last in last })

        // 1. Create tasks for running sessions without existing tasks
        for session in sessions where session.isProcessRunning {
            if !tasks.contains(where: { $0.sessionId == session.sessionId }) {
                var title = session.projectName
                if let branch = session.gitBranch, branch != "HEAD", !branch.isEmpty {
                    title += " (\(branch))"
                }
                let task = WhiplashTask(
                    title: title,
                    context: "Claude Code",
                    isAutoDetected: true,
                    sessionId: session.sessionId,
                    projectPath: session.projectPath,
                    gitBranch: session.gitBranch,
                    pid: session.pid
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

                if session.isProcessRunning {
                    // Revive if was done but session is running again
                    if tasks[i].status == .done {
                        tasks[i].status = .active
                        tasks[i].updatedAt = Date()
                        changed = true
                    }
                } else {
                    // Process not running — mark done
                    if tasks[i].status != .done {
                        tasks[i].status = .done
                        tasks[i].updatedAt = Date()
                        changed = true
                    }
                }
            } else {
                // Session not in scan results at all — mark done
                if tasks[i].status != .done {
                    tasks[i].status = .done
                    tasks[i].updatedAt = Date()
                    changed = true
                }
            }
        }

        // 4. Auto-dismiss done auto-detected tasks older than 5 minutes
        let cutoff = Date().addingTimeInterval(-300)
        let beforeCount = tasks.count
        tasks.removeAll { task in
            task.isAutoDetected && task.status == .done && task.updatedAt < cutoff
        }
        if tasks.count != beforeCount { changed = true }

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
