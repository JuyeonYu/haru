import Foundation

public enum UsageParser {

    public static func parseStatsCache(at url: URL) throws -> StatsCache {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StatsCache.self, from: data)
    }

    public static func parseStatuslinePayload(at url: URL) throws -> StatuslinePayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StatuslinePayload.self, from: data)
    }

    public static func parseSessionFile(at url: URL) throws -> [SessionMessage] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return SessionMessage.parseJSONL(content, context: url.lastPathComponent)
    }

    public static func dailyUsageFromStatsCache(_ cache: StatsCache, date: String) -> DailyUsage {
        let activity = cache.activity(for: date)
        let modelTokens = cache.modelTokens(for: date) ?? [:]
        let totalTokens = modelTokens.values.reduce(0, +)

        return DailyUsage(
            date: date,
            sessionCount: activity?.sessionCount ?? 0,
            messageCount: activity?.messageCount ?? 0,
            totalInputTokens: totalTokens,
            totalOutputTokens: 0,
            totalCacheReadTokens: 0,
            totalCacheCreationTokens: 0,
            modelsUsed: Array(modelTokens.keys)
        )
    }
}
