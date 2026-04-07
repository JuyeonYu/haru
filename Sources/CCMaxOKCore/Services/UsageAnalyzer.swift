import Foundation

public struct UsageAlert: Sendable {
    public let type: String
    public let message: String
}

public struct AlertThresholds: Sendable {
    public let overuse5hLevel1: Double  // default 80
    public let overuse5hLevel2: Double  // default 95
    public let overuse7d: Double        // default 70

    public init(overuse5hLevel1: Double = 80, overuse5hLevel2: Double = 95, overuse7d: Double = 70) {
        self.overuse5hLevel1 = overuse5hLevel1
        self.overuse5hLevel2 = overuse5hLevel2
        self.overuse7d = overuse7d
    }

    public static let `default` = AlertThresholds()
}

public enum UsageAnalyzer {

    // MARK: - Overuse Alerts

    public static func checkOveruseAlerts(rateLimits: RateLimits, thresholds: AlertThresholds = .default) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        let fh = rateLimits.fiveHour
        let sd = rateLimits.sevenDay
        let fhHoursLeft = fh.timeUntilReset / 3600

        if fh.usedPercentage >= thresholds.overuse5hLevel2 {
            let mins = Int(fh.timeUntilReset / 60)
            alerts.append(UsageAlert(
                type: "overuse_5h_95",
                message: "곧 rate limit에 걸립니다! 리셋까지 \(mins)분. 중요한 작업을 먼저 마무리하세요."
            ))
        } else if fh.usedPercentage >= thresholds.overuse5hLevel1 {
            let hours = String(format: "%.1f", fhHoursLeft)
            alerts.append(UsageAlert(
                type: "overuse_5h_80",
                message: "5시간 한도의 \(Int(fh.usedPercentage))%를 사용했어요. 리셋까지 \(hours)시간 남았습니다."
            ))
        }

        if sd.usedPercentage >= thresholds.overuse7d {
            let daysLeft = Int(sd.timeUntilReset / 86400)
            alerts.append(UsageAlert(
                type: "overuse_7d_70",
                message: "7일 한도의 \(Int(sd.usedPercentage))% 소진. 리셋까지 \(daysLeft)일 남았어요. 페이스 조절 필요."
            ))
        }

        return alerts
    }

    // MARK: - Waste Alerts

    public static func checkWasteAlerts(rateLimits: RateLimits) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        let fh = rateLimits.fiveHour
        let sd = rateLimits.sevenDay

        if fh.timeUntilReset < 3600 && fh.usedPercentage < 40 {
            let mins = Int(fh.timeUntilReset / 60)
            alerts.append(UsageAlert(
                type: "waste_5h",
                message: "\(mins)분 뒤 리셋인데 아직 \(Int(fh.remainingPercentage))%나 남았어요! 지금 쓰면 공짜예요."
            ))
        }

        if sd.timeUntilReset < 86400 && sd.usedPercentage < 50 {
            let hours = Int(sd.timeUntilReset / 3600)
            alerts.append(UsageAlert(
                type: "waste_7d",
                message: "7일 한도 리셋까지 \(hours)시간인데 \(Int(sd.usedPercentage))%밖에 안 썼어요."
            ))
        }

        return alerts
    }

    // MARK: - Pattern Recommendations

    public static func patternRecommendations(from cache: StatsCache) -> [String] {
        var recommendations: [String] = []

        let allModels = Set(cache.dailyModelTokens.values.flatMap { $0.keys })
        if allModels.count <= 1 {
            recommendations.append("간단한 작업은 Haiku로 처리하면 Opus 한도에 여유가 생겨요.")
        }

        let peak = cache.peakHours(top: 3)
        if peak.count >= 3 {
            let totalTop3 = peak.reduce(0) { $0 + $1.count }
            let totalAll = cache.hourCounts?.values.reduce(0, +) ?? 1
            if totalAll > 0 && Double(totalTop3) / Double(totalAll) > 0.6 {
                let hours = peak.map { "\($0.hour)시" }.joined(separator: ", ")
                recommendations.append("\(hours)에 몰아서 사용하시네요. 분산하면 rate limit 여유가 생겨요.")
            }
        }

        return recommendations
    }
}
