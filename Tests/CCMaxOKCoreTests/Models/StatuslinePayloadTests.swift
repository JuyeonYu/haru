import Foundation
import Testing
@testable import CCMaxOKCore

@Test func decodesStatuslinePayload() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-statusline", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let payload = try JSONDecoder().decode(StatuslinePayload.self, from: data)

    #expect(payload.sessionId == "abc123")
    #expect(payload.model.id == "claude-opus-4-6")
    #expect(payload.rateLimits?.fiveHour.usedPercentage == 42.0)
    #expect(payload.rateLimits?.sevenDay.usedPercentage == 28.0)
    #expect(payload.rateLimits?.fiveHour.resetsAt == 1775470000)
    #expect(payload.cost.totalCostUsd == 0.0)
    #expect(payload.contextWindow.totalInputTokens == 25000)
}

@Test func rateLimitStatusColor() {
    let green = RateLimitWindow(usedPercentage: 30.0, resetsAt: 0)
    let yellow = RateLimitWindow(usedPercentage: 70.0, resetsAt: 0)
    let red = RateLimitWindow(usedPercentage: 85.0, resetsAt: 0)

    #expect(green.alertLevel == .normal)
    #expect(yellow.alertLevel == .warning)
    #expect(red.alertLevel == .critical)
}

@Test func rateLimitTimeUntilReset() {
    let futureReset = Date().timeIntervalSince1970 + 3600  // 1 hour from now
    let window = RateLimitWindow(usedPercentage: 50.0, resetsAt: futureReset)
    let remaining = window.timeUntilReset

    // Should be roughly 3600 seconds (allow 5s tolerance for test execution)
    #expect(remaining > 3590)
    #expect(remaining <= 3600)
}
