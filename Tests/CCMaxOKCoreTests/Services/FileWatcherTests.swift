import Foundation
import os
import Testing
@testable import CCMaxOKCore

@Test func fileWatcherDetectsChange() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("test.json")
    try "initial".write(to: filePath, atomically: true, encoding: .utf8)

    let expectation = OSAllocatedUnfairLock(initialState: false)

    let watcher = FileWatcher(watchPaths: [tempDir.path]) {
        expectation.withLock { $0 = true }
    }
    watcher.start()

    // Wait a moment for watcher to set up
    try await Task.sleep(for: .milliseconds(100))

    // Trigger file change
    try "changed".write(to: filePath, atomically: true, encoding: .utf8)

    // Wait for callback
    try await Task.sleep(for: .seconds(1))

    let wasTriggered = expectation.withLock { $0 }
    #expect(wasTriggered)

    watcher.stop()
}
