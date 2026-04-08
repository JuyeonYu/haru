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
                    if !state.isConnected {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Claude Code 연결 안 됨")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Claude Code를 실행하면 자동으로 연결됩니다")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        RateLimitCard(
                            fiveHourPct: state.fiveHourUsedPct,
                            fiveHourResetsAt: state.fiveHourResetsAt,
                            sevenDayPct: state.sevenDayUsedPct,
                            sevenDayResetsAt: state.sevenDayResetsAt
                        )

                        TodayStatsCard(
                            sessions: state.todaySessionCount,
                            messages: state.todayMessageCount,
                            tokens: state.todayTotalTokens,
                            weekSonnetTokens: state.weekSonnetTokens
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApp.windows {
                            if String(describing: type(of: window)).contains("Settings")
                                || window.title.contains("Settings")
                                || window.title.contains("설정") {
                                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                                window.makeKeyAndOrderFront(nil)
                                window.orderFrontRegardless()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    window.collectionBehavior = [.fullScreenAuxiliary]
                                }
                            }
                        }
                    }
                })
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
