import Foundation

public struct DailyUsage: Sendable {
    public let date: String
    public let sessionCount: Int
    public let messageCount: Int
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCacheReadTokens: Int
    public let totalCacheCreationTokens: Int
    public let modelsUsed: [String]

    public var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheReadTokens + totalCacheCreationTokens
    }

    public init(date: String, sessionCount: Int = 0, messageCount: Int = 0,
                totalInputTokens: Int = 0, totalOutputTokens: Int = 0,
                totalCacheReadTokens: Int = 0, totalCacheCreationTokens: Int = 0,
                modelsUsed: [String] = []) {
        self.date = date
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCacheReadTokens = totalCacheReadTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.modelsUsed = modelsUsed
    }
}
