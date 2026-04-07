import SwiftUI

struct RateLimitCard: View {
    let fiveHourPct: Double
    let fiveHourResetsAt: Date
    let sevenDayPct: Double
    let sevenDayResetsAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rate Limits", systemImage: "gauge.medium")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            rateLimitRow(label: "5시간 한도", percentage: fiveHourPct, resetsAt: fiveHourResetsAt)
            rateLimitRow(label: "7일 한도", percentage: sevenDayPct, resetsAt: sevenDayResetsAt)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func rateLimitRow(label: String, percentage: Double, resetsAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(colorForPercentage(percentage))
            }
            ProgressView(value: min(percentage, 100), total: 100)
                .tint(colorForPercentage(percentage))
            Text("리셋: \(timeUntil(resetsAt))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func colorForPercentage(_ pct: Double) -> Color {
        if pct >= 80 { return .red }
        if pct >= 60 { return .yellow }
        return .green
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "리셋 완료" }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 24 {
            return "\(hours / 24)일 \(hours % 24)시간 후"
        }
        return "\(hours)시간 \(minutes)분 후"
    }
}
