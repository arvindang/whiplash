import Foundation

struct DetectedProcess: Sendable {
    let pid: Int32
    let command: String
    let workingDirectory: String
}

actor ProcessScanner {
    func scanForClaudeProcesses() -> [DetectedProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .components(separatedBy: "\n")
            .dropFirst() // skip header
            .compactMap { line -> DetectedProcess? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("claude") || trimmed.contains("claude-code") else {
                    return nil
                }
                // Skip our own grep/ps processes
                guard !trimmed.contains("ps -eo") else { return nil }

                let parts = trimmed.split(separator: " ", maxSplits: 1)
                guard parts.count == 2,
                      let pid = Int32(parts[0]) else { return nil }

                let command = String(parts[1])

                // Try to extract working directory from lsof
                let cwd = resolveWorkingDirectory(pid: pid)

                return DetectedProcess(
                    pid: pid,
                    command: command,
                    workingDirectory: cwd
                )
            }
    }

    private func resolveWorkingDirectory(pid: Int32) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return "" }

        // lsof output: lines starting with 'n' contain the path
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst())
            }
        }
        return ""
    }
}
