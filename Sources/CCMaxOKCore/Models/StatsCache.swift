import Foundation

public struct DailyActivity: Codable, Sendable {
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int
}

public struct ModelUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int
    public let costUSD: Double
}

public struct StatsCache: Codable, Sendable {
    public let lastComputedDate: String?
    public let totalSessions: Int
    public let totalMessages: Int
    public let dailyActivity: [String: DailyActivity]
    public let dailyModelTokens: [String: [String: Int]]
    public let modelUsage: [String: ModelUsage]?
    public let hourCounts: [String: Int]?

    public struct HourCount: Sendable {
        public let hour: String
        public let count: Int
    }

    public func peakHours(top n: Int) -> [HourCount] {
        guard let hourCounts else { return [] }
        return hourCounts
            .map { HourCount(hour: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(n)
            .map { $0 }
    }
}
