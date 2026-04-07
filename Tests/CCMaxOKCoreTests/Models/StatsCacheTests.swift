import Foundation
import Testing
@testable import CCMaxOKCore

@Test func decodesStatsCache() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let cache = try JSONDecoder().decode(StatsCache.self, from: data)

    #expect(cache.totalSessions == 250)
    #expect(cache.totalMessages == 8500)
    #expect(cache.dailyActivity.count == 2)
    #expect(cache.activity(for: "2026-04-05")?.messageCount == 120)
    #expect(cache.modelTokens(for: "2026-04-06")?["claude-opus-4-6"] == 180000)
    #expect(cache.hourCounts?["14"] == 250)
}

@Test func statsCachePeakHours() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let cache = try JSONDecoder().decode(StatsCache.self, from: data)

    let peak = cache.peakHours(top: 3)
    #expect(peak.count == 3)
    #expect(peak[0].hour == "15")  // 300 is highest
}
