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
    var hasRateLimitsData: Bool = false

    var todaySessionCount: Int = 0
    var todayMessageCount: Int = 0
    var todayTotalTokens: Int = 0

    var recommendation: Recommendation?
    var planInsight: PlanInsight?
    var patternTips: [String] = []

    var connectionState: ConnectionState = .noClaudeDir

    var isConnected: Bool {
        connectionState == .connected || connectionState == .connectedNoLimits
    }

    var isSetupComplete: Bool = false

    private var fileAccess: FileAccessManager?
    private var database: DatabaseManager?
    private var fileWatcher: FileWatcher?
    private var notificationManager: NotificationManager?

    var fiveHourAlertLevel: AlertLevel {
        if fiveHourUsedPct >= 80 { return .critical }
        if fiveHourUsedPct >= 60 { return .warning }
        return .normal
    }

    func setup() {
        let fa = FileAccessManager()
        self.fileAccess = fa

        try? fa.ensureCCMaxOKDirectory()

        if let db = try? DatabaseManager(path: fa.databasePath.path) {
            self.database = db
            self.notificationManager = NotificationManager(database: db)
            notificationManager?.requestPermission()
        }

        if !StatuslineSetup.isSetupComplete(fileAccess: fa) {
            try? StatuslineSetup.setup(fileAccess: fa)
        }
        isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fa)

        var watchPaths = [fa.ccmaxokDirectory.path]
        for dir in fa.allClaudeDirectories {
            let dirPath = dir.path
            if !watchPaths.contains(dirPath) {
                watchPaths.append(dirPath)
            }
            let projectsPath = dir.appendingPathComponent("projects", isDirectory: true).path
            if FileManager.default.fileExists(atPath: projectsPath) && !watchPaths.contains(projectsPath) {
                watchPaths.append(projectsPath)
            }
        }

        let watcher = FileWatcher(watchPaths: watchPaths) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.fileWatcher = watcher
        watcher.start()

        refresh()
        loadHistory()
    }

    func refresh() {
        guard let fileAccess else { return }

        let claudeExists = !fileAccess.allClaudeDirectories.isEmpty

        if let payload = try? UsageParser.parseStatuslinePayload(at: fileAccess.liveStatusPath) {
            if let limits = payload.rateLimits {
                connectionState = .connected
                hasRateLimitsData = true
                fiveHourUsedPct = limits.fiveHour.usedPercentage
                fiveHourResetsAt = limits.fiveHour.resetDate
                sevenDayUsedPct = limits.sevenDay.usedPercentage
                sevenDayResetsAt = limits.sevenDay.resetDate

                try? database?.insertRateLimitSnapshot(
                    timestamp: Date().timeIntervalSince1970,
                    fiveHourUsedPct: limits.fiveHour.usedPercentage,
                    fiveHourResetsAt: limits.fiveHour.resetsAt,
                    sevenDayUsedPct: limits.sevenDay.usedPercentage,
                    sevenDayResetsAt: limits.sevenDay.resetsAt,
                    model: payload.model.id
                )

                let overuse = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)
                let waste = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)
                try? notificationManager?.processAlerts(overuse + waste)

                recommendation = Recommendation.forRemainingCapacity(
                    remainingPercentage: limits.fiveHour.remainingPercentage,
                    hoursUntilReset: limits.fiveHour.timeUntilReset / 3600
                )
            } else {
                connectionState = .connectedNoLimits
                hasRateLimitsData = false
            }
        } else {
            hasRateLimitsData = false
            if !claudeExists {
                connectionState = .noClaudeDir
            } else {
                connectionState = .waitingFirstRun
            }
        }

        if let cache = try? UsageParser.parseStatsCache(at: fileAccess.statsCachePath) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayStr = formatter.string(from: Date())
            let daily = UsageParser.dailyUsageFromStatsCache(cache, date: todayStr)
            todaySessionCount = daily.sessionCount
            todayMessageCount = daily.messageCount
            todayTotalTokens = daily.totalTokens

            patternTips = UsageAnalyzer.patternRecommendations(from: cache)
        }
    }

    func loadHistory() {
        guard let fileAccess else { return }

        if let cache = try? UsageParser.parseStatsCache(at: fileAccess.statsCachePath) {
            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = Date()
            var proExceedDays = 0
            var totalUsagePct = 0.0
            var dayCount = 0

            for dayOffset in 0..<30 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                let dateStr = formatter.string(from: date)
                let daily = UsageParser.dailyUsageFromStatsCache(cache, date: dateStr)
                if daily.messageCount > 0 {
                    dayCount += 1
                    if daily.totalTokens > 500000 {
                        proExceedDays += 1
                    }
                    totalUsagePct += Double(daily.totalTokens) / 500000.0 * 100.0
                }
            }

            let avgUsage = dayCount > 0 ? totalUsagePct / Double(dayCount) : 0
            planInsight = PlanInsight.evaluate(
                proExceedDays: proExceedDays,
                totalDays: 30,
                averageDailyUsagePercent: min(avgUsage, 100)
            )
        }
    }

    func switchToPolling() {
        fileWatcher?.startPolling()
    }

    func switchToFSEvents() {
        fileWatcher?.stop()
        guard let fileAccess else { return }
        var watchPaths = [fileAccess.ccmaxokDirectory.path]
        for dir in fileAccess.allClaudeDirectories {
            let dirPath = dir.path
            if !watchPaths.contains(dirPath) {
                watchPaths.append(dirPath)
            }
        }
        let watcher = FileWatcher(watchPaths: watchPaths) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.fileWatcher = watcher
        watcher.start()
    }
}
