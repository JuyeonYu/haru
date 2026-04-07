import Foundation
import Testing
@testable import CCMaxOKCore

@Test func notificationManagerSendsWithCooldown() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("test.sqlite").path
    let db = try DatabaseManager(path: dbPath)

    let manager = NotificationManager(database: db, cooldownSeconds: 3600)

    let alert1 = UsageAlert(type: "overuse_5h_80", message: "Test alert 1")
    let shouldSend1 = try manager.shouldSend(alert: alert1)
    #expect(shouldSend1)

    try manager.recordSent(alert: alert1)

    let shouldSend2 = try manager.shouldSend(alert: alert1)
    #expect(!shouldSend2)

    // Different type should still be sendable
    let alert2 = UsageAlert(type: "waste_5h", message: "Test alert 2")
    let shouldSend3 = try manager.shouldSend(alert: alert2)
    #expect(shouldSend3)
}
