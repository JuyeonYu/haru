import Foundation

/// Anthropic OAuth `/api/oauth/usage` 응답에서 5시간/7일 윈도우 데이터를 가져오는 Tier 0 프로바이더.
///
/// statusline 훅이 호출되지 않은 시점(다른 워크스페이스에서만 사용 중, 또는 Claude Code CLI 미실행)에도
/// 정확한 사용량을 표시하기 위한 안전망. statusline 훅이 동작 중이라면 같은 데이터가 live-status.json에
/// 들어오지만, 이 경로는 statusline에 의존하지 않아 단독으로 작동한다.
///
/// 차용 출처: ai-token-monitor-main/src-tauri/src/oauth_usage.rs (호출/Keychain/응답 스키마)

/// Keychain 또는 credentials.json에서 access_token을 가져오는 의존성.
public protocol OAuthTokenSource: Sendable {
    func currentAccessToken() -> String?
}

/// HTTP 호출을 추상화 — 테스트에서 fake 주입 가능.
public protocol OAuthHTTPClient: Sendable {
    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse)
}

/// `/api/oauth/usage` 응답 구조.
public struct OAuthUsageResponse: Decodable, Sendable {
    public let fiveHour: OAuthUsageWindow?
    public let sevenDay: OAuthUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

public struct OAuthUsageWindow: Decodable, Sendable {
    /// 0.0~1.0 범위 (백분율 아님 — 사용 시 *100 필요).
    public let utilization: Double
    /// ISO 8601 형식 (예: "2026-04-25T15:30:00Z").
    public let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

public enum OAuthUsageError: Error, Sendable, Equatable {
    case noToken
    case unauthorized              // 401/403 → 사용자 재인증 필요
    case rateLimited(retryAfter: TimeInterval)
    case httpStatus(Int)
    case transport(message: String)
    case decoding(message: String)
}

public actor OAuthUsageProvider {

    public struct Configuration: Sendable {
        public var endpoint: URL
        public var betaHeader: String
        public var userAgent: String
        public var cacheTTL: TimeInterval
        public var rateLimitBackoff: TimeInterval

        public init(
            endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            betaHeader: String = "oauth-2025-04-20",
            userAgent: String = "haru/0.1 (+https://github.com/JuyeonYu)",
            cacheTTL: TimeInterval = 300,
            rateLimitBackoff: TimeInterval = 300
        ) {
            self.endpoint = endpoint
            self.betaHeader = betaHeader
            self.userAgent = userAgent
            self.cacheTTL = cacheTTL
            self.rateLimitBackoff = rateLimitBackoff
        }
    }

    private let config: Configuration
    private let tokenSource: any OAuthTokenSource
    private let http: any OAuthHTTPClient

    private var cached: (response: OAuthUsageResponse, fetchedAt: Date)?
    private var rateLimitedUntil: Date?

    public init(
        configuration: Configuration = .init(),
        tokenSource: any OAuthTokenSource,
        http: any OAuthHTTPClient
    ) {
        self.config = configuration
        self.tokenSource = tokenSource
        self.http = http
    }

    /// 5분 캐시를 거쳐 응답을 반환. 캐시 만료 또는 강제 갱신 시 네트워크 호출.
    /// 호출자가 `now`를 주입할 수 있어 테스트에서 시간 진행 시뮬레이션이 가능하다.
    public func fetchUsage(now: Date = Date()) async -> Result<OAuthUsageResponse, OAuthUsageError> {
        if let cached, now.timeIntervalSince(cached.fetchedAt) < config.cacheTTL {
            return .success(cached.response)
        }
        if let limited = rateLimitedUntil, now < limited {
            if let cached { return .success(cached.response) }
            return .failure(.rateLimited(retryAfter: limited.timeIntervalSince(now)))
        }

        guard let token = tokenSource.currentAccessToken(), !token.isEmpty else {
            return .failure(.noToken)
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": config.betaHeader,
            "Content-Type": "application/json",
            "User-Agent": config.userAgent
        ]

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.get(url: config.endpoint, headers: headers)
        } catch {
            // 네트워크 실패 시 캐시된 마지막 값 폴백 (없으면 에러 전파).
            if let cached { return .success(cached.response) }
            return .failure(.transport(message: String(describing: error)))
        }

        switch response.statusCode {
        case 200..<300:
            do {
                let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
                self.cached = (decoded, now)
                self.rateLimitedUntil = nil
                return .success(decoded)
            } catch {
                return .failure(.decoding(message: String(describing: error)))
            }
        case 401, 403:
            return .failure(.unauthorized)
        case 429:
            let retryAfter: TimeInterval = {
                if let header = response.value(forHTTPHeaderField: "Retry-After"),
                   let seconds = TimeInterval(header) {
                    return seconds
                }
                return config.rateLimitBackoff
            }()
            self.rateLimitedUntil = now.addingTimeInterval(retryAfter)
            if let cached { return .success(cached.response) }
            return .failure(.rateLimited(retryAfter: retryAfter))
        default:
            return .failure(.httpStatus(response.statusCode))
        }
    }
}

// MARK: - Production token source (Keychain + ~/.claude/.credentials.json fallback)

/// Claude Code CLI가 저장하는 OAuth 자격 증명을 읽는 기본 구현.
/// 1차: Keychain 서비스 `Claude Code-credentials` 또는 `Claude Code-credentials-{hash}` (v2.1.52+)
/// 2차: `~/.claude/.credentials.json` (또는 `CLAUDE_CONFIG_DIR`).
/// 어느 경로든 JSON 구조 `{ "claudeAiOauth": { "accessToken": "..." } }`를 기대.
public struct ClaudeCodeKeychainTokenSource: OAuthTokenSource {
    private let credentialsFileURL: URL
    private let keychainServices: [String]

    public init(homeDirectory: URL? = nil) {
        let home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        // 사용자 환경 일치: FileAccessManager의 우선순위와 동일하게 CLAUDE_CONFIG_DIR → ~/.config/claude → ~/.claude.
        let dir: URL = {
            if let envPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?.split(separator: ",").first {
                return URL(fileURLWithPath: String(envPath).trimmingCharacters(in: .whitespaces), isDirectory: true)
            }
            let configClaude = home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("claude", isDirectory: true)
            if FileManager.default.fileExists(atPath: configClaude.path) { return configClaude }
            return home.appendingPathComponent(".claude", isDirectory: true)
        }()
        self.credentialsFileURL = dir.appendingPathComponent(".credentials.json")
        self.keychainServices = ["Claude Code-credentials"]
    }

    public func currentAccessToken() -> String? {
        for service in keychainServices {
            if let token = readKeychain(service: service) { return token }
        }
        return readCredentialsFile()
    }

    private func readKeychain(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return extractAccessToken(fromJSONString: raw)
    }

    private func readCredentialsFile() -> String? {
        guard FileManager.default.fileExists(atPath: credentialsFileURL.path),
              let data = try? Data(contentsOf: credentialsFileURL),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return extractAccessToken(fromJSONString: raw)
    }

    private func extractAccessToken(fromJSONString raw: String?) -> String? {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }
}

// MARK: - Production HTTP client

public struct URLSessionOAuthHTTPClient: OAuthHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

// MARK: - Cache (UsageResolver Tier 0 진입에서 동기적으로 읽기 위한 thread-safe 컨테이너)

/// `OAuthUsageProvider`가 백그라운드 Task에서 갱신한 결과를 보관해 동기 호출자(UsageResolver)가 읽도록 한다.
public final class OAuthRateLimitsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: (limits: RateLimits, fetchedAt: Date)?

    public init() {}

    public func store(limits: RateLimits, fetchedAt: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        entry = (limits, fetchedAt)
    }

    /// `now` 시점에서 `ttl`초 이내에 가져온 값이 있으면 반환. 없으면 nil.
    public func current(now: Date = Date(), ttl: TimeInterval) -> RateLimits? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry, now.timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry.limits
    }
}

// MARK: - Conversion to RateLimits

public extension OAuthUsageResponse {
    /// utilization(0~1) → percent(0~100), ISO8601 → Date 로 변환해 기존 `RateLimits` 구조에 매핑.
    /// 두 윈도우 중 하나라도 누락되면 nil (UI는 이런 경우 데이터 없음으로 처리).
    func toRateLimits() -> RateLimits? {
        guard let five = fiveHour, let seven = sevenDay else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parse: (String) -> Double? = { iso in
            if let date = formatter.date(from: iso) {
                return date.timeIntervalSince1970
            }
            // fractional seconds 없는 경우 폴백.
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: iso)?.timeIntervalSince1970
        }
        guard let fiveResets = parse(five.resetsAt),
              let sevenResets = parse(seven.resetsAt) else { return nil }
        return RateLimits(
            fiveHour: RateLimitWindow(usedPercentage: five.utilization * 100, resetsAt: fiveResets),
            sevenDay: RateLimitWindow(usedPercentage: seven.utilization * 100, resetsAt: sevenResets)
        )
    }
}
