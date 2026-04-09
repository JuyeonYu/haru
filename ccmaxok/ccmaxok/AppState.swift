import Foundation
import CCMaxOKCore
import Observation

@Observable
@MainActor
final class AppState {
    var fiveHourUsedPct: Double = 0
    var fiveHourResetsAt: Date = .distantFuture
    var sevenDayUsedPct: Double = 0
    var sevenDayResetsAt: Date = .distantFuture

    var todaySessionCount: Int = 0
    var todayMessageCount: Int = 0
    var todayTotalTokens: Int = 0
    var weekSonnetTokens: Int = 0

    // Settings 변경 시 메뉴바 재렌더링 트리거
    var renderVersion: Int = 0

    // Claude Code 연결 상태
    var isConnected: Bool = false

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

        try? fa.ensureCCMaxOKDirectory()

        if let db = try? DatabaseManager(path: fa.databasePath.path) {
            self.database = db
        }

        if !StatuslineSetup.isSetupComplete(fileAccess: fa) {
            try? StatuslineSetup.setup(fileAccess: fa)
        }
        isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fa)

        let watcher = FileWatcher(watchPaths: [fa.ccmaxokDirectory.path]) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
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

        let fm = FileManager.default
        let claudeExists = fm.fileExists(atPath: fileAccess.claudeDirectory.path)
        let statusExists = fm.fileExists(atPath: fileAccess.liveStatusPath.path)

        if let payload = try? UsageParser.parseStatuslinePayload(at: fileAccess.liveStatusPath) {
            isConnected = true
            if let limits = payload.rateLimits {
                fiveHourUsedPct = limits.fiveHour.usedPercentage
                fiveHourResetsAt = limits.fiveHour.resetDate
                sevenDayUsedPct = limits.sevenDay.usedPercentage
                sevenDayResetsAt = limits.sevenDay.resetDate
                UserDefaults.standard.set(limits.fiveHour.usedPercentage, forKey: "ccmaxok_five_hour_used_pct")

                try? database?.insertRateLimitSnapshot(
                    timestamp: Date().timeIntervalSince1970,
                    fiveHourUsedPct: limits.fiveHour.usedPercentage,
                    fiveHourResetsAt: limits.fiveHour.resetsAt,
                    sevenDayUsedPct: limits.sevenDay.usedPercentage,
                    sevenDayResetsAt: limits.sevenDay.resetsAt,
                    model: payload.model.id
                )

            }
        } else {
            isConnected = claudeExists && statusExists
            // live-status 파싱 실패 시 DB에서 마지막 스냅샷 로드
            if let last = try? database?.rateLimitSnapshots(last: 1).first {
                fiveHourUsedPct = last.fiveHourUsedPct ?? 0
                fiveHourResetsAt = Date(timeIntervalSince1970: last.fiveHourResetsAt ?? 0)
                sevenDayUsedPct = last.sevenDayUsedPct ?? 0
                sevenDayResetsAt = Date(timeIntervalSince1970: last.sevenDayResetsAt ?? 0)
            }
        }

        // 오늘 세션/메시지 수를 JSONL 파일에서 집계
        loadTodaySessionStats()

        if let cache = try? UsageParser.parseStatsCache(at: fileAccess.statsCachePath) {
            let calendar = Calendar.current
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            let today = Date()
            let todayStr = fmt.string(from: today)

            // 오늘 토큰 (stats-cache 기준, /usage와 동일 소스)
            if let todayTokens = cache.modelTokens(for: todayStr) {
                todayTotalTokens = todayTokens.values.reduce(0, +)
            }

            // 이번 주 Sonnet 토큰
            var sonnetTotal = 0
            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                let dateStr = fmt.string(from: date)
                if let modelTokens = cache.modelTokens(for: dateStr) {
                    for (model, tokens) in modelTokens where model.lowercased().contains("sonnet") {
                        sonnetTotal += tokens
                    }
                }
            }
            weekSonnetTokens = sonnetTotal
        }
    }

    private func loadTodaySessionStats() {
        guard let fileAccess else { return }
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        do {
            let sessionFiles = try fileAccess.sessionFiles()
            var sessions = 0
            var messages = 0

            for fileURL in sessionFiles {
                // 파일 수정일이 오늘인 것만 카운트
                let attrs = try fm.attributesOfItem(atPath: fileURL.path)
                guard let modDate = attrs[.modificationDate] as? Date,
                      formatter.string(from: modDate) == todayStr else { continue }

                sessions += 1
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let msgs = SessionMessage.parseJSONL(content)
                messages += msgs.filter { $0.type == "user" }.count
            }

            todaySessionCount = sessions
            todayMessageCount = messages
        } catch {
            // 파일 접근 실패 시 기존 값 유지
        }
    }

    func switchToPolling() {
        fileWatcher?.startPolling()
    }

    func switchToFSEvents() {
        fileWatcher?.stop()
        guard let fileAccess else { return }
        let watcher = FileWatcher(watchPaths: [fileAccess.ccmaxokDirectory.path]) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.fileWatcher = watcher
        watcher.start()
    }
}
