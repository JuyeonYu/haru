import Foundation
import Testing
@testable import CCMaxOKCore

@Test func detectsOveruseAlert5h80() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 82.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 30.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 3)
    )
    let alerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "overuse_5h_80" })
}

@Test func detectsOveruseAlert5h95() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 96.0, resetsAt: Date().timeIntervalSince1970 + 1800),
        sevenDay: RateLimitWindow(usedPercentage: 50.0, resetsAt: Date().timeIntervalSince1970 + 86400)
    )
    let alerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "overuse_5h_95" })
}

@Test func detectsOveruseAlert7d70() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 20.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 75.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 2)
    )
    let alerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "overuse_7d_70" })
}

@Test func detectsWasteAlert5h() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 30.0, resetsAt: Date().timeIntervalSince1970 + 2400),
        sevenDay: RateLimitWindow(usedPercentage: 40.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 3)
    )
    let alerts = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "waste_5h" })
}

@Test func detectsWasteAlert7d() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 50.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 40.0, resetsAt: Date().timeIntervalSince1970 + 72000)
    )
    let alerts = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "waste_7d" })
}

@Test func noAlertsWhenNormal() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 50.0, resetsAt: Date().timeIntervalSince1970 + 7200),
        sevenDay: RateLimitWindow(usedPercentage: 40.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 4)
    )
    let overuse = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)
    let waste = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)

    #expect(overuse.isEmpty)
    #expect(waste.isEmpty)
}

@Test func customThresholdsAreRespected() {
    // With default thresholds, 75% 5h usage triggers level1 (80%) — should NOT fire
    // With custom thresholds (level1=60), it should fire
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 75.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 30.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 3)
    )

    let defaultAlerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)
    #expect(!defaultAlerts.contains { $0.type == "overuse_5h_80" })

    let customThresholds = AlertThresholds(overuse5hLevel1: 60, overuse5hLevel2: 90, overuse7d: 70)
    let customAlerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits, thresholds: customThresholds)
    #expect(customAlerts.contains { $0.type == "overuse_5h_80" })
}

@Test func generatesPatternRecommendation() {
    let cache = StatsCache(
        lastComputedDate: "2026-04-06",
        totalSessions: 100,
        totalMessages: 3000,
        dailyActivity: [:],
        dailyModelTokens: [
            "2026-04-05": ["claude-opus-4-6": 300000],
            "2026-04-06": ["claude-opus-4-6": 200000]
        ],
        modelUsage: nil,
        hourCounts: ["14": 200, "15": 300, "16": 250, "10": 20]
    )
    let recs = UsageAnalyzer.patternRecommendations(from: cache)

    #expect(!recs.isEmpty)
}
