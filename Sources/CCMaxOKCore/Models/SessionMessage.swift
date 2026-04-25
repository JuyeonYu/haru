import Foundation

public struct MessageUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int?
    public let cacheCreationInputTokens: Int?

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadInputTokens: Int?,
        cacheCreationInputTokens: Int?
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }

    /// Claude Code 응답의 `usage` 객체에서 토큰 필드를 추출한다.
    /// `cache_creation_input_tokens`(평탄화)이 없으면 `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}` 합산으로 폴백.
    /// 일부 응답에서 평탄화 필드가 누락되는 케이스를 ai-token-monitor 분석에서 확인.
    static func fromJSON(_ usage: [String: Any]) -> MessageUsage {
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int
        var cacheCreation = usage["cache_creation_input_tokens"] as? Int
        if cacheCreation == nil, let nested = usage["cache_creation"] as? [String: Any] {
            let fiveMin = nested["ephemeral_5m_input_tokens"] as? Int ?? 0
            let oneHour = nested["ephemeral_1h_input_tokens"] as? Int ?? 0
            let sum = fiveMin + oneHour
            if sum > 0 { cacheCreation = sum }
        }
        return MessageUsage(
            inputTokens: input,
            outputTokens: output,
            cacheReadInputTokens: cacheRead,
            cacheCreationInputTokens: cacheCreation
        )
    }
}

public struct SessionMessage: Sendable {
    public let type: String
    public let sessionId: String?
    public let messageId: String?
    public let requestId: String?
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
    ///
    /// Claude Code의 실제 jsonl은 `model`/`usage`/`id`가 `message` 객체 안에 중첩되어 있다.
    /// 단순화된 형태(top-level 필드)도 폴백으로 지원해 외부 도구나 옛 포맷도 허용한다.
    public static func parseJSONL(_ content: String, context: String = "jsonl") -> [SessionMessage] {
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
            let requestId = json["requestId"] as? String

            // 실제 Claude Code 포맷: model/usage/id는 message 객체 내부.
            // 옛 포맷·외부 도구 폴백: top-level에 있으면 그것도 허용.
            let messageDict = json["message"] as? [String: Any]
            let model = (messageDict?["model"] as? String) ?? (json["model"] as? String)
            let messageId = (messageDict?["id"] as? String) ?? (json["id"] as? String)
            let usageDict = (messageDict?["usage"] as? [String: Any]) ?? (json["usage"] as? [String: Any])

            var usage: MessageUsage? = nil
            if let u = usageDict {
                usage = MessageUsage.fromJSON(u)
            }

            messages.append(SessionMessage(
                type: type,
                sessionId: sessionId,
                messageId: messageId,
                requestId: requestId,
                model: model,
                usage: usage
            ))
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
