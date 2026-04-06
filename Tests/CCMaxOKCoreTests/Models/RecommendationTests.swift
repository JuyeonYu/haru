import Testing
@testable import CCMaxOKCore

@Test func tokenBasedRecommendationHigh() {
    let rec = Recommendation.forRemainingCapacity(
        remainingPercentage: 65.0,
        hoursUntilReset: 3.0
    )
    #expect(rec.category == .highCapacity)
    #expect(!rec.message.isEmpty)
    #expect(!rec.suggestions.isEmpty)
}

@Test func tokenBasedRecommendationMedium() {
    let rec = Recommendation.forRemainingCapacity(
        remainingPercentage: 35.0,
        hoursUntilReset: 2.0
    )
    #expect(rec.category == .mediumCapacity)
}

@Test func tokenBasedRecommendationLow() {
    let rec = Recommendation.forRemainingCapacity(
        remainingPercentage: 10.0,
        hoursUntilReset: 1.0
    )
    #expect(rec.category == .lowCapacity)
}

@Test func planInsightRecommendsProWhenLowUsage() {
    let insight = PlanInsight.evaluate(
        proExceedDays: 2,
        totalDays: 30,
        averageDailyUsagePercent: 15.0
    )
    #expect(insight.recommendation == .switchToPro)
}

@Test func planInsightRecommendsMaxWhenHighUsage() {
    let insight = PlanInsight.evaluate(
        proExceedDays: 15,
        totalDays: 30,
        averageDailyUsagePercent: 70.0
    )
    #expect(insight.recommendation == .keepMax)
}
