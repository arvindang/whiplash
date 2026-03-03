import Foundation

enum AITool: String, Sendable {
    case claude, codex, gemini

    var contextName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }

    var processName: String { rawValue }
}

struct AISession: Sendable {
    let tool: AITool
    let sessionId: String
    let projectPath: String
    let projectName: String
    let gitBranch: String?
    let pid: Int32?
    let lastActivityTimestamp: Date
    let isProcessRunning: Bool
    let terminalApp: String?
}
