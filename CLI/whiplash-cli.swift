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
    var sessionId: String?
    var projectPath: String?
    var gitBranch: String?
    var pid: Int32?
    var terminalApp: String?
    var manuallyCompleted: Bool

    enum TaskStatus: String, Codable {
        case active
        case paused
        case done
        case waiting
    }

    init(
        id: UUID = UUID(),
        title: String,
        context: String,
        status: TaskStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isAutoDetected: Bool = false,
        projectPath: String? = nil,
        gitBranch: String? = nil,
        manuallyCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isAutoDetected = isAutoDetected
        self.projectPath = projectPath
        self.gitBranch = gitBranch
        self.manuallyCompleted = manuallyCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        context = try container.decode(String.self, forKey: .context)
        status = try container.decode(TaskStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isAutoDetected = try container.decodeIfPresent(Bool.self, forKey: .isAutoDetected) ?? false
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp)
        manuallyCompleted = try container.decodeIfPresent(Bool.self, forKey: .manuallyCompleted) ?? false
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

func detectGitBranch(atPath path: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", path, "branch", "--show-current"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }
    let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return branch.isEmpty ? nil : branch
}

func addTask(title: String, context: String, projectPath: String? = nil, gitBranch: String? = nil) {
    var tasks = loadTasks()
    let task = WhiplashTask(title: title, context: context, projectPath: projectPath, gitBranch: gitBranch)
    tasks.append(task)
    saveTasks(tasks)
    var info = "Added: \(title) [\(context)]"
    if let branch = gitBranch {
        info += " (\(branch))"
    }
    info += " (\(task.id.uuidString.prefix(8)))"
    print(info)
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
        let status: String
        switch task.status {
        case .active: status = "⚡"
        case .paused: status = "⏸"
        case .waiting: status = "⏳"
        case .done: status = "✓"
        }
        let auto = task.isAutoDetected ? " (auto)" : ""
        let terminal = task.terminalApp.map { " [\($0)]" } ?? ""
        print("\(status) [\(prefix)] \(task.title) — \(task.context)\(terminal)\(auto)")
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
      whiplash add "task name" [--context "iTerm"] [--project "PATH"] [--branch "BRANCH"]
      whiplash list
      whiplash done <id-prefix>
      whiplash pause <id-prefix>
    """)
    exit(0)
}

switch args[0] {
case "add":
    guard args.count >= 2 else {
        fputs("Usage: whiplash add \"task name\" [--context \"CTX\"] [--project \"PATH\"] [--branch \"BRANCH\"]\n", stderr)
        exit(1)
    }
    let title = args[1]
    var context = "Terminal"
    var projectPath: String?
    var gitBranch: String?

    if let ctxIndex = args.firstIndex(of: "--context"), ctxIndex + 1 < args.count {
        context = args[ctxIndex + 1]
    }
    if let projIndex = args.firstIndex(of: "--project"), projIndex + 1 < args.count {
        projectPath = args[projIndex + 1]
    }
    if let branchIndex = args.firstIndex(of: "--branch"), branchIndex + 1 < args.count {
        gitBranch = args[branchIndex + 1]
    }

    // Auto-detect from $PWD when not explicitly specified
    if projectPath == nil {
        projectPath = FileManager.default.currentDirectoryPath
    }
    if gitBranch == nil, let path = projectPath {
        gitBranch = detectGitBranch(atPath: path)
    }

    addTask(title: title, context: context, projectPath: projectPath, gitBranch: gitBranch)

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
