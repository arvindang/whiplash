import Foundation

actor SessionScanner {
    private let claudeDir: URL

    init() {
        claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    var historyFileURL: URL {
        claudeDir.appendingPathComponent("history.jsonl")
    }

    func scanForSessions() -> [ClaudeSession] {
        // Phase 1: Get running claude PIDs
        let pids = getRunningClaudePIDs()

        // Phase 2: Scan session files for rich metadata
        let rawSessions = scanSessionFiles()

        // Phase 3: Match PIDs to sessions via cwd
        let pidCwds = resolvePIDWorkingDirectories(pids: pids)
        return mergeSessions(rawSessions, pidCwds: pidCwds, runningPIDs: pids)
    }

    // MARK: - Phase 1: Process Detection

    private func getRunningClaudePIDs() -> Set<Int32> {
        let output = runProcess("/usr/bin/pgrep", arguments: ["-x", "claude"])
        guard let output else { return [] }

        var pids = Set<Int32>()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int32(trimmed) {
                pids.insert(pid)
            }
        }
        return pids
    }

    // MARK: - Phase 2: Session File Scanning

    private struct RawSession {
        let sessionId: String
        let projectPath: String
        let gitBranch: String?
        let lastTimestamp: Date
    }

    private func scanSessionFiles() -> [RawSession] {
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
                if let session = parseSessionFile(file, sessionId: sessionId) {
                    results.append(session)
                }
            }
        }

        return results
    }

    private func parseSessionFile(_ url: URL, sessionId: String) -> RawSession? {
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

        return RawSession(
            sessionId: sessionId,
            projectPath: projectPath,
            gitBranch: gitBranch,
            lastTimestamp: timestamp
        )
    }

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

    // MARK: - Phase 3: PID Resolution & Merge

    private func resolvePIDWorkingDirectories(pids: Set<Int32>) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for pid in pids {
            guard let output = runProcess(
                "/usr/sbin/lsof",
                arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
            ) else { continue }

            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("n/") {
                    let path = String(line.dropFirst())
                    // Skip root directory — lsof returns "/" when cwd is unavailable
                    if path != "/" {
                        result[pid] = path
                    }
                    break
                }
            }
        }
        return result
    }

    private func mergeSessions(
        _ sessions: [RawSession],
        pidCwds: [Int32: String],
        runningPIDs: Set<Int32>
    ) -> [ClaudeSession] {
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

            return ClaudeSession(
                sessionId: session.sessionId,
                projectPath: session.projectPath,
                projectName: projectName,
                gitBranch: session.gitBranch,
                pid: matchedPID,
                lastActivityTimestamp: session.lastTimestamp,
                isProcessRunning: matchedPID != nil
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
