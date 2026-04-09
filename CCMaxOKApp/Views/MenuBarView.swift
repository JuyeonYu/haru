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
                    switch state.connectionState {
                    case .noClaudeDir:
                        VStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Claude Code 미설치")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Claude Code를 먼저 설치해주세요")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    case .waitingFirstRun:
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("데이터 대기 중")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Claude Code를 실행하면\n자동으로 데이터가 표시됩니다")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    case .connectedNoLimits:
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("연결됨")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("현재 플랜에서는 rate limit 정보가\n제공되지 않을 수 있습니다")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    case .connected:
                        if state.hasRateLimitsData {
                            RateLimitCard(
                                fiveHourPct: state.fiveHourUsedPct,
                                fiveHourResetsAt: state.fiveHourResetsAt,
                                sevenDayPct: state.sevenDayUsedPct,
                                sevenDayResetsAt: state.sevenDayResetsAt,
                                hasData: state.hasRateLimitsData
                            )
                        }
                    }

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
