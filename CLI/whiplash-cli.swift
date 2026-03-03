#!/usr/bin/env swift

import Foundation

// MARK: - Task Model (mirrors the app's model)

struct WhiplashTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var context: String
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    var isAutoDetected: Bool

    enum TaskStatus: String, Codable {
        case active
        case paused
        case done
    }

    init(
        id: UUID = UUID(),
        title: String,
        context: String,
        status: TaskStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isAutoDetected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isAutoDetected = isAutoDetected
    }
}

// MARK: - File I/O

let filePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".whiplash.json")

func loadTasks() -> [WhiplashTask] {
    guard FileManager.default.fileExists(atPath: filePath.path) else { return [] }
    do {
        let data = try Data(contentsOf: filePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([WhiplashTask].self, from: data)
    } catch {
        fputs("Error loading tasks: \(error)\n", stderr)
        return []
    }
}

func saveTasks(_ tasks: [WhiplashTask]) {
    do {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        try data.write(to: filePath, options: .atomic)
    } catch {
        fputs("Error saving tasks: \(error)\n", stderr)
    }
}

// MARK: - Commands

func addTask(title: String, context: String) {
    var tasks = loadTasks()
    let task = WhiplashTask(title: title, context: context)
    tasks.append(task)
    saveTasks(tasks)
    print("Added: \(title) [\(context)] (\(task.id.uuidString.prefix(8)))")
}

func listTasks() {
    let tasks = loadTasks()
    let active = tasks.filter { $0.status != .done }

    if active.isEmpty {
        print("No active tasks.")
        return
    }

    for task in active {
        let prefix = task.id.uuidString.prefix(8)
        let status = task.status == .paused ? "⏸" : "⚡"
        let auto = task.isAutoDetected ? " (auto)" : ""
        print("\(status) [\(prefix)] \(task.title) — \(task.context)\(auto)")
    }
}

func markDone(idPrefix: String) {
    var tasks = loadTasks()
    let lowered = idPrefix.lowercased()
    guard let index = tasks.firstIndex(where: {
        $0.id.uuidString.lowercased().hasPrefix(lowered)
    }) else {
        fputs("No task found matching '\(idPrefix)'\n", stderr)
        return
    }
    tasks[index].status = .done
    tasks[index].updatedAt = Date()
    saveTasks(tasks)
    print("Done: \(tasks[index].title)")
}

func pauseTask(idPrefix: String) {
    var tasks = loadTasks()
    let lowered = idPrefix.lowercased()
    guard let index = tasks.firstIndex(where: {
        $0.id.uuidString.lowercased().hasPrefix(lowered)
    }) else {
        fputs("No task found matching '\(idPrefix)'\n", stderr)
        return
    }
    let newStatus: WhiplashTask.TaskStatus = tasks[index].status == .paused ? .active : .paused
    tasks[index].status = newStatus
    tasks[index].updatedAt = Date()
    saveTasks(tasks)
    let action = newStatus == .paused ? "Paused" : "Resumed"
    print("\(action): \(tasks[index].title)")
}

// MARK: - Argument Parsing

let args = Array(CommandLine.arguments.dropFirst())

guard !args.isEmpty else {
    print("""
    Usage:
      whiplash add "task name" [--context "iTerm"]
      whiplash list
      whiplash done <id-prefix>
      whiplash pause <id-prefix>
    """)
    exit(0)
}

switch args[0] {
case "add":
    guard args.count >= 2 else {
        fputs("Usage: whiplash add \"task name\" [--context \"CTX\"]\n", stderr)
        exit(1)
    }
    let title = args[1]
    var context = "Terminal"
    if let ctxIndex = args.firstIndex(of: "--context"), ctxIndex + 1 < args.count {
        context = args[ctxIndex + 1]
    }
    addTask(title: title, context: context)

case "list", "ls":
    listTasks()

case "done":
    guard args.count >= 2 else {
        fputs("Usage: whiplash done <id-prefix>\n", stderr)
        exit(1)
    }
    markDone(idPrefix: args[1])

case "pause":
    guard args.count >= 2 else {
        fputs("Usage: whiplash pause <id-prefix>\n", stderr)
        exit(1)
    }
    pauseTask(idPrefix: args[1])

default:
    fputs("Unknown command: \(args[0])\n", stderr)
    exit(1)
}
