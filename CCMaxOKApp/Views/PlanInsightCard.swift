import SwiftUI
import CCMaxOKCore

struct PlanInsightCard: View {
    let insight: PlanInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("플랜 인사이트", systemImage: "chart.bar.fill")
                .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)

            Text(insight.summary).font(.caption)

            HStack {
                Label("Pro 한도 초과일", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(insight.proExceedDays)일 / \(insight.totalDays)일")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(insight.proExceedDays > 5 ? .red : .green)
            }

            Text(insight.recommendation == .keepMax ? "Max 유지 추천" : "Pro 전환 추천")
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(insight.recommendation == .keepMax ? .orange : .green)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
