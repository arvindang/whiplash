import Foundation

struct ProjectInfo: Sendable {
    let path: String
    let folderName: String
    let gitBranch: String?
}

actor SessionScanner {
    private let claudeDir: URL
    private let geminiDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDir = home.appendingPathComponent(".claude")
        geminiDir = home.appendingPathComponent(".gemini")
    }

    var historyFileURL: URL {
        claudeDir.appendingPathComponent("history.jsonl")
    }

    var geminiProjectsFileURL: URL {
        geminiDir.appendingPathComponent("projects.json")
    }

    /// Detect the project folder and git branch for a given PID.
    /// For terminal apps, walks descendant processes to find a shell with a useful cwd.
    func detectProjectInfo(forPID pid: Int32, isTerminal: Bool) -> ProjectInfo? {
        let targetPIDs: [Int32]
        if isTerminal {
            targetPIDs = findDescendantPIDs(pid)
        } else {
            targetPIDs = [pid]
        }

        var bestResult: ProjectInfo?
        for targetPID in targetPIDs {
            guard let cwd = resolveCwd(forPID: targetPID) else { continue }
            let folderName = URL(fileURLWithPath: cwd).lastPathComponent
            let branch = detectGitBranch(atPath: cwd)
            let info = ProjectInfo(path: cwd, folderName: folderName, gitBranch: branch)
            if branch != nil {
                return info // Prefer paths with git repos
            }
            if bestResult == nil {
                bestResult = info
            }
        }
        return bestResult
    }

    func scanForSessions() -> [AISession] {
        // Phase 1: Build full process table in one ps call
        let (pidsByTool, processMap) = buildProcessTable()

        // Phase 2: Scan Claude session files for rich metadata
        let claudePIDs = pidsByTool[.claude] ?? []
        let claudeSessions = scanClaudeSessions(runningPIDs: claudePIDs, processMap: processMap)

        // Phase 3: Scan Gemini session files
        let geminiPIDs = pidsByTool[.gemini] ?? []
        let geminiSessions = scanGeminiSessions(runningPIDs: geminiPIDs, processMap: processMap)

        // Phase 4: Build Codex sessions from PIDs only
        let codexPIDs = pidsByTool[.codex] ?? []
        let codexSessions = buildCodexSessions(pids: codexPIDs, processMap: processMap)

        return claudeSessions + geminiSessions + codexSessions
    }

    // MARK: - Phase 1: Process Detection

    private struct ProcessEntry {
        let ppid: Int32
        let comm: String
    }

    private func buildProcessTable() -> ([AITool: Set<Int32>], [Int32: ProcessEntry]) {
        guard let output = runProcess("/bin/ps", arguments: ["-axco", "pid,ppid,comm"]) else { return ([:], [:]) }

        var pidsByTool: [AITool: Set<Int32>] = [:]
        var processMap: [Int32: ProcessEntry] = [:]

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }
            let comm = String(parts[2])

            processMap[pid] = ProcessEntry(ppid: ppid, comm: comm)

            if let tool = AITool(rawValue: comm) {
                pidsByTool[tool, default: []].insert(pid)
            }
        }

        // Detect node-based AI CLIs (e.g., Gemini CLI runs as "node /path/to/bin/gemini")
        let nodeBasedTools: [(pattern: String, tool: AITool)] = [
            ("bin/gemini", .gemini),
        ]

        for (pattern, tool) in nodeBasedTools {
            if let output = runProcess("/usr/bin/pgrep", arguments: ["-f", pattern]) {
                for line in output.components(separatedBy: "\n") {
                    if let pid = Int32(line.trimmingCharacters(in: .whitespaces)) {
                        pidsByTool[tool, default: []].insert(pid)
                    }
                }
            }
        }

        return (pidsByTool, processMap)
    }

    // MARK: - Terminal Resolution

    private func matchTerminalName(_ comm: String) -> String? {
        switch comm {
        case "iTerm2":    return "iTerm2"
        case "Terminal":  return "Terminal"
        case "ghostty":   return "Ghostty"
        case "Warp":      return "Warp"
        case "kitty":     return "kitty"
        case "alacritty": return "Alacritty"
        case "WezTerm":   return "WezTerm"
        default: break
        }
        if comm.hasPrefix("tmux") { return "tmux" }
        return nil
    }

    private func resolveTerminalApp(forPID pid: Int32, processMap: [Int32: ProcessEntry]) -> String? {
        var current = pid
        for _ in 0..<10 {
            guard let entry = processMap[current] else { return nil }
            if let name = matchTerminalName(entry.comm) { return name }
            if entry.ppid <= 1 { return nil } // reached launchd/kernel
            current = entry.ppid
        }
        return nil
    }

    // MARK: - Claude Session Scanning

    private func scanClaudeSessions(runningPIDs: Set<Int32>, processMap: [Int32: ProcessEntry]) -> [AISession] {
        let rawSessions = scanClaudeSessionFiles()
        let pidCwds = resolvePIDWorkingDirectories(pids: runningPIDs)
        return mergeSessions(rawSessions, pidCwds: pidCwds, runningPIDs: runningPIDs, tool: .claude, processMap: processMap)
    }

    private struct RawSession {
        let sessionId: String
        let projectPath: String
        let gitBranch: String?
        let lastTimestamp: Date
        let isWaitingForInput: Bool
    }

    private func scanClaudeSessionFiles() -> [RawSession] {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var results: [RawSession] = []
        let cutoff = Date().addingTimeInterval(-600) // 10 minutes

        for projectDir in projectDirs {
            guard let isDir = try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = attrs.contentModificationDate,
                      modDate > cutoff else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                if let session = parseClaudeSessionFile(file, sessionId: sessionId) {
                    results.append(session)
                }
            }
        }

        return results
    }

    private func parseClaudeSessionFile(_ url: URL, sessionId: String) -> RawSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Read last 4KB for recent entries
        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = 4096
        let readStart = fileSize > readSize ? fileSize - readSize : 0
        handle.seek(toFileOffset: readStart)
        let data = handle.readDataToEndOfFile()

        guard let content = String(data: data, encoding: .utf8) else { return nil }

        var cwd: String?
        var gitBranch: String?
        var lastTimestamp: Date?

        // Parse lines in reverse to get most recent data first
        let lines = content.components(separatedBy: "\n").reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if cwd == nil, let c = json["cwd"] as? String {
                cwd = c
            }
            if gitBranch == nil, let b = json["gitBranch"] as? String {
                gitBranch = b
            }
            if lastTimestamp == nil {
                lastTimestamp = parseTimestamp(from: json)
            }

            // Stop once we have the essential fields
            if cwd != nil && lastTimestamp != nil {
                break
            }
        }

        guard let projectPath = cwd, let timestamp = lastTimestamp else { return nil }

        // Only show sessions where the user has sent a real prompt
        handle.seek(toFileOffset: 0)
        let headData = handle.readData(ofLength: 8192)
        guard let headContent = String(data: headData, encoding: .utf8),
              hasRealUserMessage(in: headContent) else { return nil }

        let isWaiting = detectWaitingState(in: content)

        return RawSession(
            sessionId: sessionId,
            projectPath: projectPath,
            gitBranch: gitBranch,
            lastTimestamp: timestamp,
            isWaitingForInput: isWaiting
        )
    }

    private func hasRealUserMessage(in content: String) -> Bool {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            guard json["type"] as? String == "user" else { continue }
            if json["isMeta"] as? Bool == true { continue }

            guard let message = json["message"] as? [String: Any] else { continue }
            let text: String?
            if let c = message["content"] as? String { text = c }
            else if let arr = message["content"] as? [[String: Any]] {
                text = arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            } else { text = nil }

            guard let text else { continue }
            if text.hasPrefix("<command-name>") || text.hasPrefix("<local-command") || text.hasPrefix("<system-reminder>") { continue }

            return true
        }
        return false
    }

    /// Detect whether a Claude session is waiting for user input by examining
    /// the last few JSONL entries. Returns true if the AI has finished its turn.
    private func detectWaitingState(in content: String) -> Bool {
        let lines = content.components(separatedBy: "\n").reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // turn_duration subtype means the assistant's turn just ended → waiting
            if let subtype = json["subtype"] as? String, subtype == "turn_duration" {
                return true
            }

            let type = json["type"] as? String

            // If last meaningful entry is user or has tool_use/tool_result → actively working
            if type == "user" {
                return false
            }

            if type == "assistant" {
                // Check if the assistant message contains tool_use (still working)
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    let hasToolUse = content.contains { ($0["type"] as? String) == "tool_use" }
                    if hasToolUse { return false }
                }
                // Assistant message without tool_use → waiting for user
                return true
            }

            if type == "tool_result" {
                return false
            }
        }
        return false
    }

    // MARK: - Gemini Session Scanning

    private func scanGeminiSessions(runningPIDs: Set<Int32>, processMap: [Int32: ProcessEntry]) -> [AISession] {
        let tmpDir = geminiDir.appendingPathComponent("tmp")
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-600) // 10 minutes
        var rawSessions: [RawSession] = []

        for projectDir in projectDirs {
            guard let isDir = try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            // Read .project_root for the actual project path
            let projectRootFile = projectDir.appendingPathComponent(".project_root")
            let projectPath: String
            if let rootContent = try? String(contentsOf: projectRootFile, encoding: .utf8) {
                projectPath = rootContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                continue
            }

            let chatsDir = projectDir.appendingPathComponent("chats")
            guard let chatFiles = try? fm.contentsOfDirectory(
                at: chatsDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in chatFiles where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("session-") {
                guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = attrs.contentModificationDate,
                      modDate > cutoff else { continue }

                if let session = parseGeminiSessionFile(file, projectPath: projectPath, modDate: modDate) {
                    rawSessions.append(session)
                }
            }
        }

        let pidCwds = resolvePIDWorkingDirectories(pids: runningPIDs)
        return mergeSessions(rawSessions, pidCwds: pidCwds, runningPIDs: runningPIDs, tool: .gemini, processMap: processMap)
    }

    private func parseGeminiSessionFile(_ url: URL, projectPath: String, modDate: Date) -> RawSession? {
        // Read only first 512 bytes to extract sessionId without loading full history
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headerData = handle.readData(ofLength: 512)
        var sessionId: String?
        var lastUpdated: Date = modDate

        if let headerStr = String(data: headerData, encoding: .utf8),
           let jsonData = headerStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let sid = json["sessionId"] as? String {
                sessionId = sid
            }
            if let ts = json["lastUpdated"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: ts) {
                    lastUpdated = date
                } else {
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: ts) {
                        lastUpdated = date
                    }
                }
            }
        }

        // Fall back to filename as session ID
        let fileBasedId = url.deletingPathExtension().lastPathComponent
        let finalSessionId = "gemini-\(sessionId ?? fileBasedId)"

        let gitBranch = detectGitBranch(atPath: projectPath)

        return RawSession(
            sessionId: finalSessionId,
            projectPath: projectPath,
            gitBranch: gitBranch,
            lastTimestamp: lastUpdated,
            isWaitingForInput: false
        )
    }

    // MARK: - Codex Process-Only Detection

    private func buildCodexSessions(pids: Set<Int32>, processMap: [Int32: ProcessEntry]) -> [AISession] {
        var sessions: [AISession] = []
        for pid in pids {
            guard let cwd = resolveCwd(forPID: pid) else { continue }
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent
            let gitBranch = detectGitBranch(atPath: cwd)
            let terminal = resolveTerminalApp(forPID: pid, processMap: processMap)

            sessions.append(AISession(
                tool: .codex,
                sessionId: "codex:\(cwd)",
                projectPath: cwd,
                projectName: projectName,
                gitBranch: gitBranch,
                pid: pid,
                lastActivityTimestamp: Date(),
                isProcessRunning: true,
                terminalApp: terminal,
                isWaitingForInput: false
            ))
        }
        return sessions
    }

    // MARK: - Timestamp Parsing

    private func parseTimestamp(from json: [String: Any]) -> Date? {
        if let t = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: t) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: t)
        } else if let t = json["timestamp"] as? Double {
            // Handle both seconds and milliseconds
            return t > 1_000_000_000_000
                ? Date(timeIntervalSince1970: t / 1000)
                : Date(timeIntervalSince1970: t)
        }
        return nil
    }

    // MARK: - PID Resolution & Merge

    private func resolvePIDWorkingDirectories(pids: Set<Int32>) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for pid in pids {
            if let cwd = resolveCwd(forPID: pid) {
                result[pid] = cwd
            }
        }
        return result
    }

    private func resolveCwd(forPID pid: Int32) -> String? {
        guard let output = runProcess(
            "/usr/sbin/lsof",
            arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        ) else { return nil }

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n/") {
                let path = String(line.dropFirst())
                // Skip root directory — lsof returns "/" when cwd is unavailable
                if path != "/" { return path }
                break
            }
        }
        return nil
    }

    private func findDescendantPIDs(_ parentPID: Int32, maxDepth: Int = 3) -> [Int32] {
        guard maxDepth > 0 else { return [] }
        guard let output = runProcess("/usr/bin/pgrep", arguments: ["-P", "\(parentPID)"]) else { return [] }

        var pids: [Int32] = []
        for line in output.components(separatedBy: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespaces)) {
                pids.append(pid)
                pids.append(contentsOf: findDescendantPIDs(pid, maxDepth: maxDepth - 1))
            }
        }
        return pids
    }

    private func detectGitBranch(atPath path: String) -> String? {
        guard let output = runProcess(
            "/usr/bin/git",
            arguments: ["-C", path, "branch", "--show-current"]
        ) else { return nil }
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    private func mergeSessions(
        _ sessions: [RawSession],
        pidCwds: [Int32: String],
        runningPIDs: Set<Int32>,
        tool: AITool,
        processMap: [Int32: ProcessEntry]
    ) -> [AISession] {
        var claimedPIDs = Set<Int32>()

        return sessions.map { session in
            // Find the best matching PID for this session
            var matchedPID: Int32?
            for (pid, cwd) in pidCwds where !claimedPIDs.contains(pid) {
                if cwd == session.projectPath
                    || cwd.hasPrefix(session.projectPath + "/")
                    || session.projectPath.hasPrefix(cwd + "/")
                {
                    matchedPID = pid
                    break
                }
            }

            if let pid = matchedPID {
                claimedPIDs.insert(pid)
            }

            let projectName = URL(fileURLWithPath: session.projectPath).lastPathComponent
            let terminal = matchedPID.flatMap { resolveTerminalApp(forPID: $0, processMap: processMap) }

            return AISession(
                tool: tool,
                sessionId: session.sessionId,
                projectPath: session.projectPath,
                projectName: projectName,
                gitBranch: session.gitBranch,
                pid: matchedPID,
                lastActivityTimestamp: session.lastTimestamp,
                isProcessRunning: matchedPID != nil,
                terminalApp: terminal,
                isWaitingForInput: session.isWaitingForInput
            )
        }
    }

    // MARK: - Helpers

    private func runProcess(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

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
        return String(data: data, encoding: .utf8)
    }
}
