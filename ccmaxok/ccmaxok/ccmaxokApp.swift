import SwiftUI
import CCMaxOKCore

@main
struct ccmaxokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var statusBarController: StatusBarController!
    private var refreshObserver: NSObjectProtocol?
    private var iconRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        statusBarController = StatusBarController(appState: appState)

        // appState 변경 시 아이콘 갱신
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .rendererSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.statusBarController.updateIcon()
        }

        // 파일 변경 시 아이콘 갱신
        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.statusBarController.updateIcon()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconRefreshTimer?.invalidate()
        iconRefreshTimer = nil
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
        }
    }
}

