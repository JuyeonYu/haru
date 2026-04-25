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

    /// settings.json 패치 중 primary 외의 경로에서 실패한 항목들.
    /// (CLAUDE_CONFIG_DIR에 여러 경로 지정 시 일부만 패치 성공한 경우 노출용)
    var settingsPatchFailures: [StatuslineSetup.SettingsPatchFailure] = []

    /// 로컬 SQLite(`history.sqlite`)를 열 수 없을 때 true. UI에 배지를 띄워
    /// 사용자가 stale tier나 알림 히스토리 기능이 제한됨을 인지하게 한다.
    var databaseUnavailable: Bool = false
    var databaseErrorReason: String? = nil

    private var fileAccess: FileAccessManager?
    private var database: DatabaseManager?
    private var fileWatcher: FileWatcher?
    private var currentWatchPaths: Set<String> = []

    // OAuth API Tier 0: statusline 훅이 동작하지 않는 시점에도 정확한 5시간 사용량을 받기 위한 안전망.
    // Provider는 actor라 백그라운드 Task에서 호출하고, 결과는 동기 cache에 적재해 UsageResolver가 읽는다.
    private let oauthCache = OAuthRateLimitsCache()
    private var oauthProvider: OAuthUsageProvider?
    private var oauthRefreshTask: Task<Void, Never>?

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
                let result = try StatuslineSetup.setup(fileAccess: fa)
                self.settingsPatchFailures = result.failures
                DiagnosticsLogger.shared.info("setup", "Statusline hook installed (patched \(result.succeeded.count), failed \(result.failures.count))")
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

        self.oauthProvider = OAuthUsageProvider(
            tokenSource: ClaudeCodeKeychainTokenSource(),
            http: URLSessionOAuthHTTPClient()
        )

        // 동기 초기 상태 로드 — StatusBarController.updateIcon() 호출 시점에 올바른 상태 반영
        loadInitialState(fileAccess: fa)

        installFileWatcher(fileAccess: fa)

        refresh()
        refreshOAuthInBackground()

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
        let state = UsageResolver.resolve(fileAccess: fa, database: self.database, oauthCache: oauthCache)
        apply(state: state)
    }

    /// 5분에 한 번 OAuth API를 백그라운드로 갱신. 실패는 조용히 무시(폴백 체인이 처리).
    private func refreshOAuthInBackground() {
        guard let provider = oauthProvider else { return }
        let cache = oauthCache
        // 같은 사이클의 중복 호출 방지.
        oauthRefreshTask?.cancel()
        oauthRefreshTask = Task.detached(priority: .utility) { [weak self] in
            let result = await provider.fetchUsage()
            switch result {
            case .success(let response):
                if let limits = response.toRateLimits() {
                    cache.store(limits: limits)
                    await MainActor.run {
                        self?.refresh()
                    }
                }
            case .failure(let err):
                DiagnosticsLogger.shared.info("oauth", "OAuth usage fetch skipped/failed: \(err)")
            }
        }
    }

    func refresh() {
        guard let fileAccess else {
            DiagnosticsLogger.shared.warn("app", "refresh() called before FileAccessManager is ready")
            return
        }

        // 앱 실행 후 ~/.claude가 생성됐거나 CLAUDE_CONFIG_DIR이 바뀌어 감시 대상 경로가
        // 달라졌다면 FileWatcher를 다시 만든다. 30초 heartbeat에서만 호출되므로 비용 미미.
        reevaluateWatchPathsIfNeeded(fileAccess: fileAccess)

        let fa = fileAccess
        let db = database

        let cache = oauthCache
        Task.detached(priority: .utility) {
            let state = UsageResolver.resolve(fileAccess: fa, database: db, oauthCache: cache)
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
            let result = try StatuslineSetup.setup(fileAccess: fileAccess)
            self.settingsPatchFailures = result.failures
            isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fileAccess)
            DiagnosticsLogger.shared.info("setup", "Manual re-setup completed (patched \(result.succeeded.count), failed \(result.failures.count))")
        } catch {
            DiagnosticsLogger.shared.error("setup", "Manual re-setup failed", error: error)
        }
        refresh()
    }

    func switchToPolling() {
        fileWatcher?.startPolling()
    }

    func switchToFSEvents() {
        guard let fileAccess else { return }
        installFileWatcher(fileAccess: fileAccess)
    }

    /// 시스템이 sleep에 들어가기 직전. FSEventStream이 잠든 사이 누적해
    /// wake 직후 튀우는 stale burst를 막기 위해 FileWatcher를 정지한다.
    /// wake 시 `handleSystemWake()`에서 새로 만들므로 리소스 누수 없음.
    func handleSystemWillSleep() {
        fileWatcher?.stop()
        DiagnosticsLogger.shared.info("app", "System will sleep — FileWatcher stopped")
    }

    /// 시스템이 sleep에서 복귀했을 때 FileWatcher를 새로 만들고 refresh를 강제한다.
    /// setup()은 DB 초기화·옵저버 등록 같은 1회성 작업을 포함하므로 재호출하지 않는다.
    func handleSystemWake() {
        guard let fileAccess else {
            refresh()
            return
        }
        installFileWatcher(fileAccess: fileAccess)
        refresh()
    }

    /// 감시 대상 경로가 바뀐 경우에만 FileWatcher를 재생성.
    /// `refresh()`에서 30초 주기로 호출되며, 경로 변화가 없으면 무비용.
    private func reevaluateWatchPathsIfNeeded(fileAccess: FileAccessManager) {
        let newPaths = Set(buildWatchPaths(fileAccess: fileAccess))
        guard newPaths != currentWatchPaths else { return }
        DiagnosticsLogger.shared.info(
            "app",
            "Watch paths changed — rebuilding FileWatcher (was \(currentWatchPaths.count), now \(newPaths.count))"
        )
        installFileWatcher(fileAccess: fileAccess)
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

    private func installFileWatcher(fileAccess: FileAccessManager) {
        let paths = buildWatchPaths(fileAccess: fileAccess)
        fileWatcher?.stop()
        let watcher = FileWatcher(watchPaths: paths) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.fileWatcher = watcher
        self.currentWatchPaths = Set(paths)
        watcher.start()
    }
}
