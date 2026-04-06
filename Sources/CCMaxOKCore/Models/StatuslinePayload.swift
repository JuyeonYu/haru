import Foundation

public struct StatuslineModel: Codable, Sendable {
    public let id: String
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct StatuslineCost: Codable, Sendable {
    public let totalCostUsd: Double
    public let totalDurationMs: Int
    public let totalApiDurationMs: Int
    public let totalLinesAdded: Int
    public let totalLinesRemoved: Int

    enum CodingKeys: String, CodingKey {
        case totalCostUsd = "total_cost_usd"
        case totalDurationMs = "total_duration_ms"
        case totalApiDurationMs = "total_api_duration_ms"
        case totalLinesAdded = "total_lines_added"
        case totalLinesRemoved = "total_lines_removed"
    }
}

public struct ContextWindowUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

public struct ContextWindow: Codable, Sendable {
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let usedPercentage: Double
    public let currentUsage: ContextWindowUsage
    public let contextWindowSize: Int

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case usedPercentage = "used_percentage"
        case currentUsage = "current_usage"
        case contextWindowSize = "context_window_size"
    }
}

public struct StatuslinePayload: Codable, Sendable {
    public let sessionId: String
    public let model: StatuslineModel
    public let cost: StatuslineCost
    public let contextWindow: ContextWindow
    public let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case model
        case cost
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }
}
