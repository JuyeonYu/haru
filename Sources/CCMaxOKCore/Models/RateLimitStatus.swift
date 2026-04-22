import Foundation

public enum AlertLevel: Sendable {
    case normal    // 0-60%
    case warning   // 60-80%
    case critical  // 80%+
}

public struct RateLimitWindow: Codable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Double

    public init(usedPercentage: Double, resetsAt: Double) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var alertLevel: AlertLevel {
        if usedPercentage >= 80 { return .critical }
        if usedPercentage >= 60 { return .warning }
        return .normal
    }

    public var timeUntilReset: TimeInterval {
        max(0, resetsAt - Date().timeIntervalSince1970)
    }

    public var resetDate: Date {
        Date(timeIntervalSince1970: resetsAt)
    }

    public var remainingPercentage: Double {
        max(0, 100.0 - usedPercentage)
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercentage = try c.decode(Double.self, forKey: .usedPercentage)
        let raw = try c.decode(Double.self, forKey: .resetsAt)
        // Claude Code는 resets_at을 초 단위 Unix timestamp로 내보낸다.
        // 만약 미래에 밀리초 단위로 바뀌면 raw가 현재 시각의 10배 이상이 되므로 감지해 보정.
        let now = Date().timeIntervalSince1970
        if raw > now * 10 {
            self.resetsAt = raw / 1000
            DiagnosticsLogger.shared.warn(
                "parser",
                "resets_at looked like milliseconds (raw=\(raw)); divided by 1000"
            )
        } else {
            self.resetsAt = raw
        }
    }
}

public struct RateLimits: Codable, Sendable {
    public let fiveHour: RateLimitWindow
    public let sevenDay: RateLimitWindow

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
