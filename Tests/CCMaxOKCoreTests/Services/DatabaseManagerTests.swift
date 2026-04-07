import Foundation
import Testing
@testable import CCMaxOKCore

@Test func createsDatabaseAndTables() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("test.sqlite").path
    let db = try DatabaseManager(path: dbPath)

    try db.insertRateLimitSnapshot(
        timestamp: Date().timeIntervalSince1970,
        fiveHourUsedPct: 42.0,
        fiveHourResetsAt: Date().timeIntervalSince1970 + 3600,
        sevenDayUsedPct: 28.0,
        sevenDayResetsAt: Date().timeIntervalSince1970 + 86400,
        model: "claude-opus-4-6"
    )

    let snapshots = try db.rateLimitSnapshots(last: 10)
    #expect(snapshots.count == 1)
    #expect(snapshots[0].fiveHourUsedPct == 42.0)
}

@Test func insertAndQueryDailyUsage() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("test.sqlite").path
    let db = try DatabaseManager(path: dbPath)

    let usage = DailyUsage(
        date: "2026-04-06",
        sessionCount: 5,
        messageCount: 85,
        totalInputTokens: 100000,
        totalOutputTokens: 25000,
        modelsUsed: ["claude-opus-4-6"]
    )
    try db.upsertDailyUsage(usage)

    let result = try db.dailyUsage(from: "2026-04-01", to: "2026-04-07")
    #expect(result.count == 1)
    #expect(result[0].messageCount == 85)
}

@Test func insertNotificationLog() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("test.sqlite").path
    let db = try DatabaseManager(path: dbPath)

    try db.logNotification(type: "overuse_5h_80", message: "Test alert")

    let canSend = try db.canSendNotification(type: "overuse_5h_80", cooldownSeconds: 3600)
    #expect(!canSend)

    let canSendOther = try db.canSendNotification(type: "waste_5h", cooldownSeconds: 3600)
    #expect(canSendOther)
}
