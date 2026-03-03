import Foundation

struct WhiplashTask: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var context: String
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    var isAutoDetected: Bool

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
