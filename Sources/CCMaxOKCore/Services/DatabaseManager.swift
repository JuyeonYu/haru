import Foundation
import SQLite

public final class DatabaseManager: @unchecked Sendable {
    private let db: Connection

    // MARK: - Tables
    private static let rateLimitSnapshots = Table("rate_limit_snapshots")
    private static let rlId = SQLite.Expression<Int64>("id")
    private static let rlTimestamp = SQLite.Expression<Double>("timestamp")
    private static let rlFiveHourPct = SQLite.Expression<Double?>("five_hour_used_pct")
    private static let rlFiveHourReset = SQLite.Expression<Double?>("five_hour_resets_at")
    private static let rlSevenDayPct = SQLite.Expression<Double?>("seven_day_used_pct")
    private static let rlSevenDayReset = SQLite.Expression<Double?>("seven_day_resets_at")
    private static let rlModel = SQLite.Expression<String?>("model")

    private static let dailyUsageTable = Table("daily_usage")
    private static let duDate = SQLite.Expression<String>("date")
    private static let duSessionCount = SQLite.Expression<Int>("session_count")
    private static let duMessageCount = SQLite.Expression<Int>("message_count")
    private static let duInputTokens = SQLite.Expression<Int>("total_input_tokens")
    private static let duOutputTokens = SQLite.Expression<Int>("total_output_tokens")
    private static let duCacheReadTokens = SQLite.Expression<Int>("total_cache_read_tokens")
    private static let duCacheCreationTokens = SQLite.Expression<Int>("total_cache_creation_tokens")
    private static let duModelsUsed = SQLite.Expression<String?>("models_used")

    private static let notificationLog = Table("notification_log")
    private static let nlId = SQLite.Expression<Int64>("id")
    private static let nlTimestamp = SQLite.Expression<Double>("timestamp")
    private static let nlType = SQLite.Expression<String>("type")
    private static let nlMessage = SQLite.Expression<String?>("message")

    public init(path: String) throws {
        db = try Connection(path)
        try createTables()
    }

    private func createTables() throws {
        try db.run(Self.rateLimitSnapshots.create(ifNotExists: true) { t in
            t.column(Self.rlId, primaryKey: .autoincrement)
            t.column(Self.rlTimestamp)
            t.column(Self.rlFiveHourPct)
            t.column(Self.rlFiveHourReset)
            t.column(Self.rlSevenDayPct)
            t.column(Self.rlSevenDayReset)
            t.column(Self.rlModel)
        })

        try db.run(Self.dailyUsageTable.create(ifNotExists: true) { t in
            t.column(Self.duDate, primaryKey: true)
            t.column(Self.duSessionCount, defaultValue: 0)
            t.column(Self.duMessageCount, defaultValue: 0)
            t.column(Self.duInputTokens, defaultValue: 0)
            t.column(Self.duOutputTokens, defaultValue: 0)
            t.column(Self.duCacheReadTokens, defaultValue: 0)
            t.column(Self.duCacheCreationTokens, defaultValue: 0)
            t.column(Self.duModelsUsed)
        })

        try db.run(Self.notificationLog.create(ifNotExists: true) { t in
            t.column(Self.nlId, primaryKey: .autoincrement)
            t.column(Self.nlTimestamp)
            t.column(Self.nlType)
            t.column(Self.nlMessage)
        })
    }

    // MARK: - Rate Limit Snapshots

    public struct RateLimitRow: Sendable {
        public let timestamp: Double
        public let fiveHourUsedPct: Double?
        public let fiveHourResetsAt: Double?
        public let sevenDayUsedPct: Double?
        public let sevenDayResetsAt: Double?
        public let model: String?
    }

    public func insertRateLimitSnapshot(
        timestamp: Double, fiveHourUsedPct: Double?, fiveHourResetsAt: Double?,
        sevenDayUsedPct: Double?, sevenDayResetsAt: Double?, model: String?
    ) throws {
        try db.run(Self.rateLimitSnapshots.insert(
            Self.rlTimestamp <- timestamp,
            Self.rlFiveHourPct <- fiveHourUsedPct,
            Self.rlFiveHourReset <- fiveHourResetsAt,
            Self.rlSevenDayPct <- sevenDayUsedPct,
            Self.rlSevenDayReset <- sevenDayResetsAt,
            Self.rlModel <- model
        ))
    }

    public func rateLimitSnapshots(last n: Int) throws -> [RateLimitRow] {
        try db.prepare(
            Self.rateLimitSnapshots
                .order(Self.rlTimestamp.desc)
                .limit(n)
        ).map { row in
            RateLimitRow(
                timestamp: row[Self.rlTimestamp],
                fiveHourUsedPct: row[Self.rlFiveHourPct],
                fiveHourResetsAt: row[Self.rlFiveHourReset],
                sevenDayUsedPct: row[Self.rlSevenDayPct],
                sevenDayResetsAt: row[Self.rlSevenDayReset],
                model: row[Self.rlModel]
            )
        }
    }

    // MARK: - Daily Usage

    public func upsertDailyUsage(_ usage: DailyUsage) throws {
        let modelsJson = try String(data: JSONEncoder().encode(usage.modelsUsed), encoding: .utf8)
        try db.run(Self.dailyUsageTable.insert(or: .replace,
            Self.duDate <- usage.date,
            Self.duSessionCount <- usage.sessionCount,
            Self.duMessageCount <- usage.messageCount,
            Self.duInputTokens <- usage.totalInputTokens,
            Self.duOutputTokens <- usage.totalOutputTokens,
            Self.duCacheReadTokens <- usage.totalCacheReadTokens,
            Self.duCacheCreationTokens <- usage.totalCacheCreationTokens,
            Self.duModelsUsed <- modelsJson
        ))
    }

    public func dailyUsage(from startDate: String, to endDate: String) throws -> [DailyUsage] {
        try db.prepare(
            Self.dailyUsageTable
                .filter(Self.duDate >= startDate && Self.duDate <= endDate)
                .order(Self.duDate.asc)
        ).map { row in
            let modelsJson = row[Self.duModelsUsed] ?? "[]"
            let models = (try? JSONDecoder().decode([String].self, from: Data(modelsJson.utf8))) ?? []
            return DailyUsage(
                date: row[Self.duDate],
                sessionCount: row[Self.duSessionCount],
                messageCount: row[Self.duMessageCount],
                totalInputTokens: row[Self.duInputTokens],
                totalOutputTokens: row[Self.duOutputTokens],
                totalCacheReadTokens: row[Self.duCacheReadTokens],
                totalCacheCreationTokens: row[Self.duCacheCreationTokens],
                modelsUsed: models
            )
        }
    }

    // MARK: - Notification Log

    public func logNotification(type: String, message: String) throws {
        try db.run(Self.notificationLog.insert(
            Self.nlTimestamp <- Date().timeIntervalSince1970,
            Self.nlType <- type,
            Self.nlMessage <- message
        ))
    }

    public func canSendNotification(type: String, cooldownSeconds: Double) throws -> Bool {
        let cutoff = Date().timeIntervalSince1970 - cooldownSeconds
        let count = try db.scalar(
            Self.notificationLog
                .filter(Self.nlType == type && Self.nlTimestamp > cutoff)
                .count
        )
        return count == 0
    }
}
