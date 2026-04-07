import SwiftUI
import CCMaxOKCore

struct MenuBarView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("CCMaxOK")
                    .font(.headline)
                Text("Claude Code Usage Monitor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    RateLimitCard(
                        fiveHourPct: state.fiveHourUsedPct,
                        fiveHourResetsAt: state.fiveHourResetsAt,
                        sevenDayPct: state.sevenDayUsedPct,
                        sevenDayResetsAt: state.sevenDayResetsAt
                    )

                    TodayStatsCard(
                        sessions: state.todaySessionCount,
                        messages: state.todayMessageCount,
                        tokens: state.todayTotalTokens
                    )

                    if let rec = state.recommendation {
                        RecommendationCard(recommendation: rec, tips: state.patternTips)
                    }

                    if let insight = state.planInsight {
                        PlanInsightCard(insight: insight)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
