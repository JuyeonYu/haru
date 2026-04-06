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

public struct SessionMessage: Codable, Sendable {
    public let type: String
    public let timestamp: String
    public let sessionId: String
    public let model: String?
    public let usage: MessageUsage?
    public let message: String?

    public struct TokenTotals: Sendable {
        public let input: Int
        public let output: Int
        public let cacheRead: Int
        public let cacheCreation: Int

        public var total: Int { input + output + cacheRead + cacheCreation }
    }

    public static func parseJSONL(_ content: String) -> [SessionMessage] {
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionMessage.self, from: data)
            }
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
