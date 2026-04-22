import Foundation
import Testing
@testable import CCMaxOKCore

@Test func resolvesClaudeDirectory() {
    let fam = FileAccessManager()
    let claudeDir = fam.claudeDirectory
    #expect(claudeDir.path().contains(".claude"))
}

@Test func resolvesCCMaxOKDirectory() {
    let fam = FileAccessManager()
    let appDir = fam.ccmaxokDirectory
    #expect(appDir.path().contains(".claude/ccmaxok"))
}

@Test func liveStatusPath() {
    let fam = FileAccessManager()
    let path = fam.liveStatusPath
    #expect(path.path().hasSuffix("live-status.json"))
}

@Test func statsCachePath() {
    let fam = FileAccessManager()
    let path = fam.statsCachePath
    #expect(path.path().hasSuffix("stats-cache.json"))
}

@Test func settingsPath() {
    let fam = FileAccessManager()
    let path = fam.settingsPath
    #expect(path.path().hasSuffix("settings.json"))
}

@Test func resolveEncodedProjectPathHandlesSimpleCase() throws {
    // 나이브 케이스: 실제 경로에 `-`가 없는 경우 1차 디코드로 즉시 해결 (A3 기존 동작 유지).
    let tmp = try makeTempDir(subdirs: ["simple-case-\(UUID().uuidString)", "sub"])
    defer { try? FileManager.default.removeItem(at: tmp.root) }
    // tmp/<uuid>/sub 경로. 인코딩 시 모든 `/`가 `-`로 치환된다고 가정.
    let encoded = "-" + tmp.target.path.replacingOccurrences(of: "/", with: "-")
    let resolved = FileAccessManager.resolveEncodedProjectPath(encoded)
    #expect(resolved?.standardizedFileURL == tmp.target.standardizedFileURL)
}

@Test func resolveEncodedProjectPathReconstructsHyphenatedSegment() throws {
    // 실제 경로에 `-`가 포함된 경우: 1차 나이브 실패 → heuristic으로 복구 (A3 핵심).
    let uniq = "hy-\(UUID().uuidString.prefix(8))-proj"
    let tmp = try makeTempDir(subdirs: [String(uniq), "haru"])
    defer { try? FileManager.default.removeItem(at: tmp.root) }

    let encoded = "-" + tmp.target.path.replacingOccurrences(of: "/", with: "-")
    let resolved = FileAccessManager.resolveEncodedProjectPath(encoded)
    #expect(resolved?.standardizedFileURL == tmp.target.standardizedFileURL)
}

@Test func resolveEncodedProjectPathReturnsNilWhenUnresolvable() {
    // 존재하지 않는 경로는 nil을 돌려줘 상위 호출자가 로깅 후 skip할 수 있게 해야 한다.
    let resolved = FileAccessManager.resolveEncodedProjectPath("-nonexistent-random-\(UUID().uuidString)-path")
    #expect(resolved == nil)
}

// MARK: - helpers

private struct TempDirs {
    let root: URL
    let target: URL
}

private func makeTempDir(subdirs: [String]) throws -> TempDirs {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("haru-path-test-\(UUID().uuidString)")
    var current = root
    for s in subdirs {
        current = current.appendingPathComponent(s, isDirectory: true)
    }
    try fm.createDirectory(at: current, withIntermediateDirectories: true)
    return TempDirs(root: root, target: current)
}
