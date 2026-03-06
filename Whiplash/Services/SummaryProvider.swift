import Foundation

actor SummaryProvider {
    private var cache: [String: String] = [:]

    func summary(for task: WhiplashTask) async -> String? {
        guard let sessionId = task.sessionId,
              let projectPath = task.projectPath else {
            return nil
        }

        if let cached = cache[sessionId] {
            return cached
        }

        // v1: Only Claude Code sessions supported
        guard task.context.lowercased().contains("claude") else {
            return nil
        }

        let fileURL = sessionFileURL(projectPath: projectPath, sessionId: sessionId)
        let result = extractFirstUserMessage(from: fileURL)

        if let result {
            cache[sessionId] = result
        }
        return result
    }

    func invalidate(sessionId: String) {
        cache.removeValue(forKey: sessionId)
    }

    private func sessionFileURL(projectPath: String, sessionId: String) -> URL {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "-")
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encoded)
            .appendingPathComponent("\(sessionId).jsonl")
    }

    private func extractFirstUserMessage(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Read first 8KB to find the initial user query
        let data = handle.readData(ofLength: 8192)

        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            guard json["type"] as? String == "user" else { continue }
            if json["isMeta"] as? Bool == true { continue }

            guard let message = json["message"] as? [String: Any] else { continue }

            var text: String?
            if let content = message["content"] as? String {
                text = content
            } else if let contentArr = message["content"] as? [[String: Any]] {
                text = contentArr.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            }

            guard var text else { continue }
            if text.hasPrefix("<command-name>") || text.hasPrefix("<local-command") || text.hasPrefix("<system-reminder>") || text.hasPrefix("[Request interrupted") { continue }

            // Take first line only, truncate for display
            text = text.components(separatedBy: "\n").first ?? text
            if text.count > 120 {
                text = String(text.prefix(117)) + "..."
            }
            return text
        }
        return nil
    }
}
