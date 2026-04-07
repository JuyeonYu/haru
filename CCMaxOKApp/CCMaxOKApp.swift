import SwiftUI
import CCMaxOKCore

@main
struct CCMaxOKApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appState)
                .frame(width: 320)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(iconColor)
                    .font(.system(size: 8))
                Text("\(Int(appState.fiveHourUsedPct))%")
                    .font(.system(size: 11, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appState.switchToFSEvents()
            case .background:
                appState.switchToPolling()
            default:
                break
            }
        }
        .onAppear {
            appState.setup()
        }

        Settings {
            SettingsView()
        }
    }

    private var iconColor: Color {
        switch appState.fiveHourAlertLevel {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
