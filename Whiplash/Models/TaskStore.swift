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

    func addAutoDetectedTask(title: String, context: String) {
        // Don't add duplicates
        guard !tasks.contains(where: { $0.title == title && $0.isAutoDetected }) else { return }
        let task = WhiplashTask(title: title, context: context, isAutoDetected: true)
        tasks.append(task)
        saveTasks()
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
