import SwiftUI
import CCMaxOKCore

struct RecommendationCard: View {
    let recommendation: Recommendation
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("추천", systemImage: "lightbulb.fill")
                .font(.caption).foregroundStyle(.green).textCase(.uppercase)

            Text(recommendation.message).font(.caption)

            ForEach(recommendation.suggestions, id: \.self) { suggestion in
                Label(suggestion, systemImage: "arrow.right.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if !tips.isEmpty {
                Divider()
                ForEach(tips, id: \.self) { tip in
                    Label(tip, systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
