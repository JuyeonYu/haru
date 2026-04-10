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
        connectionState == .connected || connectionState == .connectedNoLimits
    }

    var isSetupComplete: Bool = false

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
        let fa = FileAccessManager()
        self.fileAccess = fa

        do {
            try fa.ensureCCMaxOKDirectory()
        } catch {
            CCMaxOKCore.logger.error("Failed to create ccmaxok directory: \(error.localizedDescription)")
        }

        do {
            self.database = try DatabaseManager(path: fa.databasePath.path)
        } catch {
            CCMaxOKCore.logger.error("Failed to initialize database: \(error.localizedDescription)")
        }

        if !StatuslineSetup.isSetupComplete(fileAccess: fa) {
            do {
                try StatuslineSetup.setup(fileAccess: fa)
            } catch {
                CCMaxOKCore.logger.error("Statusline setup failed: \(error.localizedDescription)")
            }
        }
        isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fa)

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

    func refresh() {
        guard let fileAccess else { return }

        let fa = fileAccess
        let db = database

        Task.detached(priority: .utility) {
            let claudeExists = !fa.allClaudeDirectories.isEmpty
            let payload = try? UsageParser.parseStatuslinePayload(at: fa.liveStatusPath)
            let cache = try? UsageParser.parseStatsCache(at: fa.statsCachePath)
            let sessionStats = Self.computeSessionStats(fileAccess: fa)

            let lastSnapshot: DatabaseManager.RateLimitRow? = {
                guard payload?.rateLimits == nil else { return nil }
                return (try? db?.rateLimitSnapshots(last: 1))?.first
            }()

            // DB 쓰기 (백그라운드)
            if let limits = payload?.rateLimits, let model = payload?.model.id {
                do {
                    try db?.insertRateLimitSnapshot(
                        timestamp: Date().timeIntervalSince1970,
                        fiveHourUsedPct: limits.fiveHour.usedPercentage,
                        fiveHourResetsAt: limits.fiveHour.resetsAt,
                        sevenDayUsedPct: limits.sevenDay.usedPercentage,
                        sevenDayResetsAt: limits.sevenDay.resetsAt,
                        model: model
                    )
                } catch {
                    CCMaxOKCore.logger.error("Failed to insert rate limit snapshot: \(error.localizedDescription)")
                }
            }

            // 토큰 집계 (백그라운드)
            var todayTokens = 0
            var sonnetTotal = 0
            if let cache {
                let calendar = Calendar.current
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                let today = Date()
                let todayStr = fmt.string(from: today)

                if let tokens = cache.modelTokens(for: todayStr) {
                    todayTokens = tokens.values.reduce(0, +)
                }

                for dayOffset in 0..<7 {
                    guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                    let dateStr = fmt.string(from: date)
                    if let modelTokens = cache.modelTokens(for: dateStr) {
                        for (model, tokens) in modelTokens where model.lowercased().contains("sonnet") {
                            sonnetTotal += tokens
                        }
                    }
                }
            }

            // UI 업데이트 (메인 스레드)
            await MainActor.run {
                if let payload {
                    if let limits = payload.rateLimits {
                        self.connectionState = .connected
                        self.hasRateLimitsData = true
                        self.fiveHourUsedPct = limits.fiveHour.usedPercentage
                        self.fiveHourResetsAt = limits.fiveHour.resetDate
                        self.sevenDayUsedPct = limits.sevenDay.usedPercentage
                        self.sevenDayResetsAt = limits.sevenDay.resetDate
                        UserDefaults.standard.set(limits.fiveHour.usedPercentage, forKey: "ccmaxok_five_hour_used_pct")
                    } else {
                        self.connectionState = .connectedNoLimits
                        self.hasRateLimitsData = false
                    }
                } else {
                    self.hasRateLimitsData = false
                    self.connectionState = claudeExists ? .waitingFirstRun : .noClaudeDir

                    if let last = lastSnapshot {
                        self.fiveHourUsedPct = last.fiveHourUsedPct ?? 0
                        self.fiveHourResetsAt = Date(timeIntervalSince1970: last.fiveHourResetsAt ?? 0)
                        self.sevenDayUsedPct = last.sevenDayUsedPct ?? 0
                        self.sevenDayResetsAt = Date(timeIntervalSince1970: last.sevenDayResetsAt ?? 0)
                    }
                }

                self.todaySessionCount = sessionStats.sessions
                self.todayMessageCount = sessionStats.messages
                self.todayTotalTokens = todayTokens
                self.weekSonnetTokens = sonnetTotal
            }
        }
    }

    nonisolated private static func computeSessionStats(fileAccess: FileAccessManager) -> (sessions: Int, messages: Int) {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        do {
            let sessionFiles = try fileAccess.sessionFiles()
            var sessions = 0
            var messages = 0

            for fileURL in sessionFiles {
                let attrs = try fm.attributesOfItem(atPath: fileURL.path)
                guard let modDate = attrs[.modificationDate] as? Date,
                      formatter.string(from: modDate) == todayStr else { continue }

                sessions += 1
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let msgs = SessionMessage.parseJSONL(content)
                messages += msgs.filter { $0.type == "user" }.count
            }

            return (sessions, messages)
        } catch {
            CCMaxOKCore.logger.warning("Failed to load today session stats: \(error.localizedDescription)")
            return (0, 0)
        }
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
