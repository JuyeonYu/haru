import SwiftUI

struct RateLimitCard: View {
    let fiveHourPct: Double
    let fiveHourResetsAt: Date
    let sevenDayPct: Double
    let sevenDayResetsAt: Date
    let hasData: Bool

    private static let fiveHourWindow: TimeInterval = 5 * 3600
    private static let sevenDayWindow: TimeInterval = 7 * 24 * 3600

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(spacing: 8) {
                rateLimitGroup(
                    icon: "bolt.fill",
                    label: "5시간 세션",
                    percentage: fiveHourPct,
                    resetsAt: fiveHourResetsAt,
                    totalWindow: Self.fiveHourWindow
                )
                rateLimitGroup(
                    icon: "calendar.badge.clock",
                    label: "7일 세션",
                    percentage: sevenDayPct,
                    resetsAt: sevenDayResetsAt,
                    totalWindow: Self.sevenDayWindow
                )
            }
        }
    }

    @ViewBuilder
    private func rateLimitGroup(icon: String, label: String, percentage: Double, resetsAt: Date, totalWindow: TimeInterval) -> some View {
        let remaining = max(0, resetsAt.timeIntervalSinceNow)
        let elapsedPct = min(100, (1 - remaining / totalWindow) * 100)
        let remainPct = max(0, 100 - percentage)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasData {
                    Text("\(Int(remainPct))% 남음")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(colorForRemaining(remainPct))
                } else {
                    Text("—")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: hasData ? remainPct : 0, total: 100)
                .tint(hasData ? colorForRemaining(remainPct) : .secondary)

            HStack {
                Text("리셋")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if hasData {
                    Text(timeUntil(resetsAt))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(colorForReset(elapsedPct))
                } else {
                    Text("데이터 없음")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func colorForRemaining(_ pct: Double) -> Color {
        if pct > 50 { return .green }
        if pct > 0 { return .yellow }
        return .red
    }

    private func colorForReset(_ elapsedPct: Double) -> Color {
        if elapsedPct >= 80 { return .green }
        if elapsedPct >= 50 { return .yellow }
        return .secondary
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return String(localized: "리셋 완료") }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 24 {
            return String(localized: "\(hours / 24)일 \(hours % 24)시간 \(minutes)분 후")
        }
        return String(localized: "\(hours)시간 \(minutes)분 후")
    }
}
