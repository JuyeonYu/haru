import Foundation
import Testing
@testable import CCMaxOKCore

@Test func concurrentInserts() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("test.sqlite").path
    let db = try DatabaseManager(path: dbPath)

    let iterations = 50
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

    for i in 0..<iterations {
        group.enter()
        queue.async {
            defer { group.leave() }
            try? db.insertRateLimitSnapshot(
                timestamp: Date().timeIntervalSince1970 + Double(i),
                fiveHourUsedPct: Double(i),
                fiveHourResetsAt: nil,
                sevenDayUsedPct: nil,
                sevenDayResetsAt: nil,
                model: "test-model"
            )
        }
    }

    group.wait()

    let snapshots = try db.rateLimitSnapshots(last: 100)
    #expect(snapshots.count == iterations)
}

@Test func concurrentReadWrite() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("test.sqlite").path
    let db = try DatabaseManager(path: dbPath)

    let group = DispatchGroup()
    let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

    // Concurrent writes
    for i in 0..<20 {
        group.enter()
        queue.async {
            defer { group.leave() }
            try? db.insertRateLimitSnapshot(
                timestamp: Double(i),
                fiveHourUsedPct: Double(i),
                fiveHourResetsAt: nil,
                sevenDayUsedPct: nil,
                sevenDayResetsAt: nil,
                model: nil
            )
        }
    }

    // Concurrent reads
    for _ in 0..<20 {
        group.enter()
        queue.async {
            defer { group.leave() }
            _ = try? db.rateLimitSnapshots(last: 10)
        }
    }

    group.wait()

    let snapshots = try db.rateLimitSnapshots(last: 100)
    #expect(snapshots.count == 20)
}
