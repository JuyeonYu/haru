import SwiftUI

struct RateLimitCard: View {
    let fiveHourPct: Double
    let fiveHourResetsAt: Date
    let sevenDayPct: Double
    let sevenDayResetsAt: Date

    private static let fiveHourWindow: TimeInterval = 5 * 3600
    private static let sevenDayWindow: TimeInterval = 7 * 24 * 3600

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("사용량", systemImage: "gauge.medium")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            rateLimitRow(label: "5시간", percentage: fiveHourPct, resetsAt: fiveHourResetsAt, totalWindow: Self.fiveHourWindow)
            rateLimitRow(label: "7일", percentage: sevenDayPct, resetsAt: sevenDayResetsAt, totalWindow: Self.sevenDayWindow)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func rateLimitRow(label: String, percentage: Double, resetsAt: Date, totalWindow: TimeInterval) -> some View {
        let remaining = max(0, resetsAt.timeIntervalSinceNow)
        let elapsedPct = min(100, (1 - remaining / totalWindow) * 100)
        let remainPct = max(0, 100 - percentage)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(Int(remainPct))%")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(colorForRemaining(remainPct))
            }
            ProgressView(value: remainPct, total: 100)
                .tint(colorForRemaining(remainPct))

            HStack {
                Text("리셋").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(timeUntil(resetsAt))
                    .font(.caption2).fontWeight(.medium)
                    .foregroundStyle(colorForReset(elapsedPct))
            }
            ProgressView(value: elapsedPct, total: 100)
                .tint(colorForReset(elapsedPct))
        }
    }

    // 잔여량 색상: 메뉴바 아이콘과 동일
    private func colorForRemaining(_ pct: Double) -> Color {
        if pct > 50 { return .green }
        if pct > 0 { return .yellow }
        return .red
    }

    // 리셋 시간 색상: 리셋 임박 = 곧 회복 = 초록
    private func colorForReset(_ elapsedPct: Double) -> Color {
        if elapsedPct >= 80 { return .green }
        if elapsedPct >= 50 { return .yellow }
        return .secondary
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "리셋 완료" }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 24 {
            return "\(hours / 24)일 \(hours % 24)시간 \(minutes)분 후"
        }
        return "\(hours)시간 \(minutes)분 후"
    }
}
