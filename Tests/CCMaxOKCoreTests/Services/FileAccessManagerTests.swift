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
