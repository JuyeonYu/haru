import Foundation
import Testing
@testable import CCMaxOKCore

@Suite("OAuthUsageProvider")
struct OAuthUsageProviderTests {

    @Test func decodesUsageAndConvertsUtilizationToPercent() async {
        let body = """
        {
          "five_hour": { "utilization": 0.14, "resets_at": "2026-04-25T15:30:00Z" },
          "seven_day": { "utilization": 0.5,  "resets_at": "2026-05-01T00:00:00Z" }
        }
        """
        let provider = OAuthUsageProvider(
            tokenSource: FakeTokenSource(token: "tk"),
            http: FakeHTTPClient(status: 200, body: body)
        )

        let result = await provider.fetchUsage()
        guard case .success(let response) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(response.fiveHour?.utilization == 0.14)
        guard let limits = response.toRateLimits() else {
            Issue.record("toRateLimits returned nil despite both windows present")
            return
        }
        // utilization 0.14 → percentage 14.0 (0~100 정규화).
        #expect(abs(limits.fiveHour.usedPercentage - 14.0) < 0.0001)
        #expect(abs(limits.sevenDay.usedPercentage - 50.0) < 0.0001)
        // ISO 8601 → Unix epoch 변환 (2026-04-25T15:30:00Z = 1777131000).
        #expect(Int(limits.fiveHour.resetsAt) == 1777131000)
    }

    @Test func returnsNoTokenWhenSourceEmpty() async {
        let provider = OAuthUsageProvider(
            tokenSource: FakeTokenSource(token: nil),
            http: FakeHTTPClient(status: 200, body: "{}")
        )
        let result = await provider.fetchUsage()
        #expect(result == .failure(.noToken))
    }

    @Test func unauthorizedOn401() async {
        let provider = OAuthUsageProvider(
            tokenSource: FakeTokenSource(token: "tk"),
            http: FakeHTTPClient(status: 401, body: "{}")
        )
        let result = await provider.fetchUsage()
        #expect(result == .failure(.unauthorized))
    }

    @Test func rateLimitedOn429ReturnsRetryAfterFromHeader() async {
        let provider = OAuthUsageProvider(
            tokenSource: FakeTokenSource(token: "tk"),
            http: FakeHTTPClient(status: 429, body: "{}", headers: ["Retry-After": "60"])
        )
        let result = await provider.fetchUsage()
        if case .failure(.rateLimited(let retry)) = result {
            #expect(retry == 60)
        } else {
            Issue.record("expected rateLimited, got \(result)")
        }
    }

    @Test func cacheServesWithinTTL() async {
        let body = """
        { "five_hour": { "utilization": 0.1, "resets_at": "2026-04-25T15:30:00Z" },
          "seven_day": { "utilization": 0.2, "resets_at": "2026-05-01T00:00:00Z" } }
        """
        let http = CountingHTTPClient(status: 200, body: body)
        let provider = OAuthUsageProvider(
            tokenSource: FakeTokenSource(token: "tk"),
            http: http
        )
        // 첫 호출: 네트워크 1회.
        _ = await provider.fetchUsage(now: Date(timeIntervalSince1970: 1_000_000))
        // TTL(300s) 안의 두 번째 호출은 캐시 hit — 네트워크 호출 안 일어남.
        _ = await provider.fetchUsage(now: Date(timeIntervalSince1970: 1_000_100))
        let count = await http.count()
        #expect(count == 1)

        // TTL 경과 시 다시 네트워크 호출.
        _ = await provider.fetchUsage(now: Date(timeIntervalSince1970: 1_000_500))
        let count2 = await http.count()
        #expect(count2 == 2)
    }

    @Test func cacheStoresAndReadsCurrent() {
        let cache = OAuthRateLimitsCache()
        let limits = RateLimits(
            fiveHour: RateLimitWindow(usedPercentage: 14, resetsAt: 1777131000),
            sevenDay: RateLimitWindow(usedPercentage: 50, resetsAt: 1777582800)
        )
        let now = Date(timeIntervalSince1970: 1_000_000)
        cache.store(limits: limits, fetchedAt: now)
        // TTL 안.
        #expect(cache.current(now: now.addingTimeInterval(60), ttl: 300)?.fiveHour.usedPercentage == 14)
        // TTL 밖.
        #expect(cache.current(now: now.addingTimeInterval(400), ttl: 300) == nil)
    }
}

// MARK: - Fakes

private struct FakeTokenSource: OAuthTokenSource {
    let token: String?
    func currentAccessToken() -> String? { token }
}

private struct FakeHTTPClient: OAuthHTTPClient {
    let status: Int
    let body: String
    let headers: [String: String]

    init(status: Int, body: String, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: self.headers
        )!
        return (Data(body.utf8), response)
    }
}

private actor CountingHTTPClient: OAuthHTTPClient {
    let status: Int
    let body: String
    private var calls = 0

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func count() -> Int { calls }

    nonisolated func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        await record()
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }

    private func record() {
        calls += 1
    }
}

// `Result<OAuthUsageResponse, OAuthUsageError>`의 == 비교를 위해 (테스트에서만 사용).
private func == (
    lhs: Result<OAuthUsageResponse, OAuthUsageError>,
    rhs: Result<OAuthUsageResponse, OAuthUsageError>
) -> Bool {
    switch (lhs, rhs) {
    case (.failure(let a), .failure(let b)):
        return a == b
    default:
        return false
    }
}
