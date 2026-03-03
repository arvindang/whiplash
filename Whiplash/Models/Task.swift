import Foundation

struct WhiplashTask: Identifiable, Codable, Sendable {
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

    enum TaskStatus: String, Codable, Sendable {
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
        isAutoDetected: Bool = false,
        sessionId: String? = nil,
        projectPath: String? = nil,
        gitBranch: String? = nil,
        pid: Int32? = nil,
        terminalApp: String? = nil
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isAutoDetected = isAutoDetected
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.gitBranch = gitBranch
        self.pid = pid
        self.terminalApp = terminalApp
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
    }
}
