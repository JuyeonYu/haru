import Foundation

public struct UsageAlert: Sendable {
    public let type: String
    public let message: String
}

public struct AlertThresholds: Sendable {
    public let remain5hLevel1: Double  // 잔여 % 이하일 때 1단계 (default 50)
    public let remain5hLevel2: Double  // 잔여 % 이하일 때 2단계 (default 10)
    public let remain7d: Double        // 잔여 % 이하일 때 (default 30)
    public let waste5hTimeWindow: TimeInterval   // 리셋까지 이 시간(초) 이내면 낭비 알림 (default 3600)
    public let waste5hUsedBelow: Double          // 사용률이 이 % 미만이면 낭비 (default 40)
    public let waste7dTimeWindow: TimeInterval   // 7일 리셋까지 이 시간(초) 이내 (default 86400)
    public let waste7dUsedBelow: Double          // 사용률이 이 % 미만이면 낭비 (default 50)

    public init(
        remain5hLevel1: Double = 50,
        remain5hLevel2: Double = 10,
        remain7d: Double = 30,
        waste5hTimeWindow: TimeInterval = 3600,
        waste5hUsedBelow: Double = 40,
        waste7dTimeWindow: TimeInterval = 86400,
        waste7dUsedBelow: Double = 50
    ) {
        self.remain5hLevel1 = remain5hLevel1
        self.remain5hLevel2 = remain5hLevel2
        self.remain7d = remain7d
        self.waste5hTimeWindow = waste5hTimeWindow
        self.waste5hUsedBelow = waste5hUsedBelow
        self.waste7dTimeWindow = waste7dTimeWindow
        self.waste7dUsedBelow = waste7dUsedBelow
    }

    public static let `default` = AlertThresholds()
}

public enum UsageAnalyzer {

    // MARK: - Overuse Alerts

    public static func checkOveruseAlerts(rateLimits: RateLimits, thresholds: AlertThresholds = .default) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        let fh = rateLimits.fiveHour
        let sd = rateLimits.sevenDay
        let fhRemain = fh.remainingPercentage
        let sdRemain = sd.remainingPercentage
        let fhHoursLeft = fh.timeUntilReset / 3600

        if fhRemain <= thresholds.remain5hLevel2 {
            let mins = Int(fh.timeUntilReset / 60)
            alerts.append(UsageAlert(
                type: "overuse_5h_95",
                message: String(localized: "잔여 \(Int(fhRemain))%! 곧 rate limit에 걸립니다. 리셋까지 \(mins)분.", bundle: .module)
            ))
        } else if fhRemain <= thresholds.remain5hLevel1 {
            let hours = String(format: "%.1f", fhHoursLeft)
            alerts.append(UsageAlert(
                type: "overuse_5h_80",
                message: String(localized: "5시간 한도 잔여 \(Int(fhRemain))%. 리셋까지 \(hours)시간 남았습니다.", bundle: .module)
            ))
        }

        if sdRemain <= thresholds.remain7d {
            let daysLeft = Int(sd.timeUntilReset / 86400)
            alerts.append(UsageAlert(
                type: "overuse_7d_70",
                message: String(localized: "7일 한도 잔여 \(Int(sdRemain))%. 리셋까지 \(daysLeft)일 남았어요.", bundle: .module)
            ))
        }

        return alerts
    }

    // MARK: - Waste Alerts

    public static func checkWasteAlerts(rateLimits: RateLimits, thresholds: AlertThresholds = .default) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        let fh = rateLimits.fiveHour
        let sd = rateLimits.sevenDay

        if fh.timeUntilReset < thresholds.waste5hTimeWindow && fh.usedPercentage < thresholds.waste5hUsedBelow {
            let mins = Int(fh.timeUntilReset / 60)
            alerts.append(UsageAlert(
                type: "waste_5h",
                message: String(localized: "\(mins)분 뒤 리셋인데 아직 \(Int(fh.remainingPercentage))%나 남았어요! 지금 쓰면 공짜예요.", bundle: .module)
            ))
        }

        if sd.timeUntilReset < thresholds.waste7dTimeWindow && sd.usedPercentage < thresholds.waste7dUsedBelow {
            let hours = Int(sd.timeUntilReset / 3600)
            alerts.append(UsageAlert(
                type: "waste_7d",
                message: String(localized: "7일 한도 리셋까지 \(hours)시간인데 \(Int(sd.usedPercentage))%밖에 안 썼어요.", bundle: .module)
            ))
        }

        return alerts
    }

    // MARK: - Pattern Recommendations

    public static func patternRecommendations(from cache: StatsCache) -> [String] {
        var recommendations: [String] = []

        let allModels = Set(cache.dailyModelTokens.flatMap { $0.tokensByModel.keys })
        if allModels.count <= 1 {
            recommendations.append(String(localized: "간단한 작업은 Haiku로 처리하면 Opus 한도에 여유가 생겨요.", bundle: .module))
        }

        let peak = cache.peakHours(top: 3)
        if peak.count >= 3 {
            let totalTop3 = peak.reduce(0) { $0 + $1.count }
            let totalAll = cache.hourCounts?.values.reduce(0, +) ?? 1
            if totalAll > 0 && Double(totalTop3) / Double(totalAll) > 0.6 {
                let hours = peak.map { "\($0.hour)시" }.joined(separator: ", ")
                recommendations.append(String(localized: "\(hours)에 몰아서 사용하시네요. 분산하면 rate limit 여유가 생겨요.", bundle: .module))
            }
        }

        return recommendations
    }
}
