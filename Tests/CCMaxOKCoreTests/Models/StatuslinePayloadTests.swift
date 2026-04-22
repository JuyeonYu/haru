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

@Test func detectsMillisecondsAndConvertsToSeconds() throws {
    // Claude Code가 미래에 resets_at을 밀리초로 보내도 초 단위로 보정되어야 한다 (A4).
    // 현재 시각을 밀리초로 표현한 값 → 초 단위로 변환되어 resetDate가 대략 지금이 되어야 함.
    let nowSec = Date().timeIntervalSince1970
    let nowMillis = nowSec * 1000
    let json = "{\"used_percentage\": 50.0, \"resets_at\": \(Int64(nowMillis))}"
    let window = try JSONDecoder().decode(RateLimitWindow.self, from: Data(json.utf8))

    // 보정된 resetsAt은 원본 초 단위와 5초 이내 차이여야 함.
    #expect(abs(window.resetsAt - nowSec) < 5)
}

@Test func keepsSecondsWhenWithinExpectedRange() throws {
    // 정상적인 초 단위 timestamp는 그대로 유지되어야 한다 (A4).
    let nowSec = Date().timeIntervalSince1970 + 7200  // 2시간 뒤
    let json = "{\"used_percentage\": 50.0, \"resets_at\": \(nowSec)}"
    let window = try JSONDecoder().decode(RateLimitWindow.self, from: Data(json.utf8))
    #expect(abs(window.resetsAt - nowSec) < 0.001)
}
