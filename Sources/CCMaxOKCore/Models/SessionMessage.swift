import Foundation

public struct MessageUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int?
    public let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

public struct SessionMessage: Sendable {
    public let type: String
    public let sessionId: String?
    public let model: String?
    public let usage: MessageUsage?

    public struct TokenTotals: Sendable {
        public let input: Int
        public let output: Int
        public let cacheRead: Int
        public let cacheCreation: Int

        public var total: Int { input + output + cacheRead + cacheCreation }
    }

    /// Parse JSONL loosely — only extract fields we need, skip unknown structure.
    /// `context`는 경고 로그에 함께 남길 식별자(파일명 등). 스킵 줄이 비정상적으로 많으면 1회 warn.
    public static func parseJSONL(_ content: String, context: String = "jsonl") -> [SessionMessage] {
        // CRLF / CR 단독 라인 구분자도 허용 (외부 툴이 저장한 파일 대비).
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var skipped = 0
        var total = 0
        var messages: [SessionMessage] = []
        messages.reserveCapacity(64)

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            total += 1
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                skipped += 1
                continue
            }

            let sessionId = json["sessionId"] as? String
            let model = json["model"] as? String

            var usage: MessageUsage? = nil
            if let usageDict = json["usage"] as? [String: Any] {
                usage = MessageUsage(
                    inputTokens: usageDict["input_tokens"] as? Int ?? 0,
                    outputTokens: usageDict["output_tokens"] as? Int ?? 0,
                    cacheReadInputTokens: usageDict["cache_read_input_tokens"] as? Int,
                    cacheCreationInputTokens: usageDict["cache_creation_input_tokens"] as? Int
                )
            }

            messages.append(SessionMessage(type: type, sessionId: sessionId, model: model, usage: usage))
        }

        if total > 0 && (skipped > 5 || Double(skipped) / Double(total) > 0.05) {
            DiagnosticsLogger.shared.warn(
                "session-parser",
                "\(context): skipped \(skipped)/\(total) malformed JSONL lines"
            )
        }
        return messages
    }

    public static func totalTokens(_ messages: [SessionMessage]) -> TokenTotals {
        var input = 0, output = 0, cacheRead = 0, cacheCreation = 0
        for msg in messages {
            guard let usage = msg.usage else { continue }
            input += usage.inputTokens
            output += usage.outputTokens
            cacheRead += usage.cacheReadInputTokens ?? 0
            cacheCreation += usage.cacheCreationInputTokens ?? 0
        }
        return TokenTotals(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
    }
}
