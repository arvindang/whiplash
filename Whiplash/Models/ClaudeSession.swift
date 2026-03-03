import Foundation

struct ClaudeSession: Sendable {
    let sessionId: String
    let projectPath: String
    let projectName: String
    let gitBranch: String?
    let pid: Int32?
    let lastActivityTimestamp: Date
    let isProcessRunning: Bool
}
