import AppKit
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
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var iconRefreshTimer: Timer?
    private var dataRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        statusBarController = StatusBarController(appState: appState)

        // 렌더러 설정 변경 시 아이콘 즉시 갱신
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .rendererSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusBarController.updateIcon()
            }
        }

        // 5초 UI 틱: 리셋 카운트다운 표시용 (데이터 재조회 없음)
        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusBarController.updateIcon()
            }
        }

        // 30초 heartbeat: FSEvents가 놓친 변화나 sleep 외 알 수 없는 상황의 안전망
        dataRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.appState.refresh()
            }
        }

        // Sleep 직전: FileWatcher 정지. FSEvents가 잠든 사이 스테일 이벤트를 큐잉해
        // wake 직후 의미 없는 refresh를 번쩍 튀우는 것을 방지.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.appState.handleSystemWillSleep()
            }
        }

        // Sleep 복귀 시 FileWatcher 재시작 + 강제 refresh
        // NSWorkspace 알림은 shared.notificationCenter로만 관찰 가능
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.appState.handleSystemWake()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 앱이 포커스를 받을 때마다 싼 보험으로 refresh
        guard let appState else { return }
        appState.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconRefreshTimer?.invalidate()
        iconRefreshTimer = nil
        dataRefreshTimer?.invalidate()
        dataRefreshTimer = nil
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
    }
}

