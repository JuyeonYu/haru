import Foundation

public enum CapacityCategory: Sendable {
    case highCapacity   // >50% remaining
    case mediumCapacity // 20-50% remaining
    case lowCapacity    // <20% remaining
}

public struct Recommendation: Sendable {
    public let category: CapacityCategory
    public let message: String
    public let suggestions: [String]

    public static func forRemainingCapacity(
        remainingPercentage: Double,
        hoursUntilReset: Double
    ) -> Recommendation {
        if remainingPercentage > 50 {
            return Recommendation(
                category: .highCapacity,
                message: "여유가 많아요! 큰 작업을 하기 좋은 때예요.",
                suggestions: [
                    "프로젝트 리팩토링",
                    "테스트 커버리지 올리기",
                    "코드 문서화"
                ]
            )
        } else if remainingPercentage > 20 {
            return Recommendation(
                category: .mediumCapacity,
                message: "적당히 남았어요. 중간 규모 작업에 활용하세요.",
                suggestions: [
                    "코드 리뷰",
                    "버그 수정",
                    "유닛 테스트 추가"
                ]
            )
        } else {
            return Recommendation(
                category: .lowCapacity,
                message: "한도가 얼마 안 남았어요. 가볍게 사용하세요.",
                suggestions: [
                    "짧은 질문",
                    "문서 검토",
                    "간단한 수정"
                ]
            )
        }
    }
}

public enum PlanRecommendation: Sendable {
    case keepMax
    case switchToPro
}

public struct PlanInsight: Sendable {
    public let recommendation: PlanRecommendation
    public let proExceedDays: Int
    public let totalDays: Int
    public let averageDailyUsagePercent: Double
    public let summary: String

    public static func evaluate(
        proExceedDays: Int,
        totalDays: Int,
        averageDailyUsagePercent: Double
    ) -> PlanInsight {
        let shouldSwitchToPro = proExceedDays <= 5 && averageDailyUsagePercent < 40.0

        let recommendation: PlanRecommendation = shouldSwitchToPro ? .switchToPro : .keepMax

        let summary: String
        if shouldSwitchToPro {
            summary = "지난 \(totalDays)일 중 Pro 한도 초과일: \(proExceedDays)일. Pro 전환을 고려해보세요."
        } else {
            summary = "지난 \(totalDays)일 중 Pro 한도 초과일: \(proExceedDays)일. Max 유지를 추천합니다."
        }

        return PlanInsight(
            recommendation: recommendation,
            proExceedDays: proExceedDays,
            totalDays: totalDays,
            averageDailyUsagePercent: averageDailyUsagePercent,
            summary: summary
        )
    }
}
