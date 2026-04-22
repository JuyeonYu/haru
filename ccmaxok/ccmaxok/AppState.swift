import Foundation
import CCMaxOKCore
import Observation
import os

@Observable
@MainActor
final class AppState {
    var fiveHourUsedPct: Double = 0
    var fiveHourResetsAt: Date = .distantFuture
    var sevenDayUsedPct: Double = 0
    var sevenDayResetsAt: Date = .distantFuture
    var hasRateLimitsData: Bool = false

    var todaySessionCount: Int = 0
    var todayMessageCount: Int = 0
    var todayTotalTokens: Int = 0
    var weekSonnetTokens: Int = 0

    // Settings 변경 시 메뉴바 재렌더링 트리거
    var renderVersion: Int = 0

    // Claude Code 연결 상태
    var connectionState: ConnectionState = .noClaudeDir

    var isConnected: Bool {
        switch connectionState {
        case .connected, .connectedNoLimits, .stale, .derived:
            return true
        case .noClaudeDir, .waitingFirstRun:
            return false
        }
    }

    var isStale: Bool {
        switch connectionState {
        case .stale, .derived: return true
        default: return false
        }
    }

    var diagnosticErrorCount: Int {
        DiagnosticsLogger.shared.errorCount
    }

    var isSetupComplete: Bool = false

    var statuslineConflicts: [StatuslineSetup.StatuslineConflict] = []

    /// 로컬 SQLite(`history.sqlite`)를 열 수 없을 때 true. UI에 배지를 띄워
    /// 사용자가 stale tier나 알림 히스토리 기능이 제한됨을 인지하게 한다.
    var databaseUnavailable: Bool = false
    var databaseErrorReason: String? = nil

    private var fileAccess: FileAccessManager?
    private var database: DatabaseManager?
    private var fileWatcher: FileWatcher?

    init() {
        setup()
    }

    var fiveHourAlertLevel: AlertLevel {
        let remaining = 100 - fiveHourUsedPct
        if remaining <= 0 { return .critical }
        if remaining < 50 { return .warning }
        return .normal
    }

    func setup() {
        DiagnosticsLogger.shared.info("app", "Launching haru (core v\(CCMaxOKCore.version))")

        let fa = FileAccessManager()
        self.fileAccess = fa

        do {
            try fa.ensureCCMaxOKDirectory()
        } catch {
            DiagnosticsLogger.shared.error("app", "Failed to create ccmaxok directory at \(fa.ccmaxokDirectory.path)", error: error)
        }

        do {
            self.database = try DatabaseManager(path: fa.databasePath.path)
            self.databaseUnavailable = false
            self.databaseErrorReason = nil
        } catch {
            self.database = nil
            self.databaseUnavailable = true
            self.databaseErrorReason = error.localizedDescription
            DiagnosticsLogger.shared.error("app", "Failed to initialize database at \(fa.databasePath.path)", error: error)
        }

        if !StatuslineSetup.isSetupComplete(fileAccess: fa) {
            do {
                try StatuslineSetup.setup(fileAccess: fa)
                DiagnosticsLogger.shared.info("setup", "Statusline hook installed")
            } catch {
                DiagnosticsLogger.shared.error("setup", "Statusline setup failed", error: error)
            }
        } else if StatuslineSetup.scriptNeedsUpdate(fileAccess: fa) {
            do {
                try StatuslineSetup.deployScript(fileAccess: fa)
                DiagnosticsLogger.shared.info("setup", "Statusline script updated to use absolute paths")
            } catch {
                DiagnosticsLogger.shared.error("setup", "Statusline script update failed", error: error)
            }
        }
        isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fa)

        // 동기 초기 상태 로드 — StatusBarController.updateIcon() 호출 시점에 올바른 상태 반영
        loadInitialState(fileAccess: fa)

        let watcher = makeFileWatcher(fileAccess: fa)
        self.fileWatcher = watcher
        watcher.start()

        refresh()

        NotificationCenter.default.addObserver(
            forName: .rendererSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.renderVersion += 1
            }
        }
    }

    private func loadInitialState(fileAccess fa: FileAccessManager) {
        let state = UsageResolver.resolve(fileAccess: fa, database: self.database)
        apply(state: state)
    }

    func refresh() {
        guard let fileAccess else {
            DiagnosticsLogger.shared.warn("app", "refresh() called before FileAccessManager is ready")
            return
        }

        let fa = fileAccess
        let db = database

        Task.detached(priority: .utility) {
            let state = UsageResolver.resolve(fileAccess: fa, database: db)
            let conflicts = StatuslineSetup.projectLocalStatuslineConflicts(fileAccess: fa)

            // Persist live-only snapshots to the DB so the stale-fallback path has data later.
            if case .resolved(let snap) = state,
               snap.freshness == .live,
               let fiveHourPct = snap.fiveHourUsedPct,
               let sevenDayPct = snap.sevenDayUsedPct,
               let fiveHourReset = snap.fiveHourResetsAt,
               let sevenDayReset = snap.sevenDayResetsAt {
                do {
                    try db?.insertRateLimitSnapshot(
                        timestamp: Date().timeIntervalSince1970,
                        fiveHourUsedPct: fiveHourPct,
                        fiveHourResetsAt: fiveHourReset.timeIntervalSince1970,
                        sevenDayUsedPct: sevenDayPct,
                        sevenDayResetsAt: sevenDayReset.timeIntervalSince1970,
                        model: snap.model
                    )
                } catch {
                    DiagnosticsLogger.shared.error("db", "Failed to insert rate limit snapshot", error: error)
                }
            }

            await MainActor.run {
                self.apply(state: state)
                self.statuslineConflicts = conflicts
            }
        }
    }

    private func apply(state: UsageResolver.State) {
        switch state {
        case .noClaudeDir:
            self.connectionState = .noClaudeDir
            self.hasRateLimitsData = false

        case .waitingFirstRun:
            self.connectionState = .waitingFirstRun
            self.hasRateLimitsData = false

        case .resolved(let snap):
            self.fiveHourUsedPct = snap.fiveHourUsedPct ?? 0
            self.fiveHourResetsAt = snap.fiveHourResetsAt ?? .distantFuture
            self.sevenDayUsedPct = snap.sevenDayUsedPct ?? 0
            self.sevenDayResetsAt = snap.sevenDayResetsAt ?? .distantFuture
            self.hasRateLimitsData = snap.hasRateLimits
            self.todaySessionCount = snap.todaySessionCount
            self.todayMessageCount = snap.todayMessageCount
            self.todayTotalTokens = snap.todayTokens
            self.weekSonnetTokens = snap.weekSonnetTokens

            switch snap.freshness {
            case .live:
                self.connectionState = snap.hasRateLimits ? .connected : .connectedNoLimits
                if let pct = snap.fiveHourUsedPct {
                    UserDefaults.standard.set(pct, forKey: "ccmaxok_five_hour_used_pct")
                }
            case .stale(let asOf):
                self.connectionState = .stale(asOf: asOf)
            case .derived(let asOf):
                self.connectionState = .derived(asOf: asOf)
            }
        }
    }

    func retrySetup() {
        guard let fileAccess else { return }
        do {
            try StatuslineSetup.setup(fileAccess: fileAccess)
            isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fileAccess)
            DiagnosticsLogger.shared.info("setup", "Manual re-setup completed")
        } catch {
            DiagnosticsLogger.shared.error("setup", "Manual re-setup failed", error: error)
        }
        refresh()
    }

    func switchToPolling() {
        fileWatcher?.startPolling()
    }

    func switchToFSEvents() {
        fileWatcher?.stop()
        guard let fileAccess else { return }
        let watcher = makeFileWatcher(fileAccess: fileAccess)
        self.fileWatcher = watcher
        watcher.start()
    }

    /// 시스템이 sleep에서 복귀했을 때 FileWatcher를 새로 만들고 refresh를 강제한다.
    /// setup()은 DB 초기화·옵저버 등록 같은 1회성 작업을 포함하므로 재호출하지 않는다.
    func handleSystemWake() {
        guard let fileAccess else {
            refresh()
            return
        }
        fileWatcher?.stop()
        let watcher = makeFileWatcher(fileAccess: fileAccess)
        self.fileWatcher = watcher
        watcher.start()
        refresh()
    }

    private func buildWatchPaths(fileAccess: FileAccessManager) -> [String] {
        var watchPaths = [fileAccess.ccmaxokDirectory.path]
        for dir in fileAccess.allClaudeDirectories {
            let dirPath = dir.path
            if !watchPaths.contains(dirPath) {
                watchPaths.append(dirPath)
            }
            let projectsPath = dir.appendingPathComponent("projects", isDirectory: true).path
            if FileManager.default.fileExists(atPath: projectsPath) && !watchPaths.contains(projectsPath) {
                watchPaths.append(projectsPath)
            }
        }
        return watchPaths
    }

    private func makeFileWatcher(fileAccess: FileAccessManager) -> FileWatcher {
        FileWatcher(watchPaths: buildWatchPaths(fileAccess: fileAccess)) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
