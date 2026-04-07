import SwiftUI

struct TodayStatsCard: View {
    let sessions: Int
    let messages: Int
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("오늘", systemImage: "calendar")
                .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: 0) {
                statItem(value: "\(sessions)", label: "세션")
                Spacer()
                statItem(value: "\(messages)", label: "메시지")
                Spacer()
                statItem(value: formatTokens(tokens), label: "토큰")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).fontWeight(.bold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.0fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
