import Foundation
import Testing
@testable import CCMaxOKCore

@Test func parsesStatsCache() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let cache = try UsageParser.parseStatsCache(at: url)

    #expect(cache.totalSessions == 250)
    #expect(cache.dailyActivity.count == 2)
}

@Test func parsesStatuslinePayload() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-statusline", withExtension: "json")!
    let payload = try UsageParser.parseStatuslinePayload(at: url)

    #expect(payload.rateLimits?.fiveHour.usedPercentage == 42.0)
    #expect(payload.sessionId == "abc123")
}

@Test func parsesSessionFile() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-session", withExtension: "jsonl")!
    let messages = try UsageParser.parseSessionFile(at: url)

    #expect(messages.count == 4)
    let assistants = messages.filter { $0.type == "assistant" }
    #expect(assistants.count == 2)
}

@Test func aggregatesDailyUsageFromStatsCache() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let cache = try UsageParser.parseStatsCache(at: url)
    let daily = UsageParser.dailyUsageFromStatsCache(cache, date: "2026-04-05")

    #expect(daily.date == "2026-04-05")
    #expect(daily.sessionCount == 8)
    #expect(daily.messageCount == 120)
    #expect(daily.modelsUsed.contains("claude-opus-4-6"))
}
