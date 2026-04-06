import Foundation

public enum AlertLevel: Sendable {
    case normal    // 0-60%
    case warning   // 60-80%
    case critical  // 80%+
}

public struct RateLimitWindow: Codable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Double

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
}

public struct RateLimits: Codable, Sendable {
    public let fiveHour: RateLimitWindow
    public let sevenDay: RateLimitWindow

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
