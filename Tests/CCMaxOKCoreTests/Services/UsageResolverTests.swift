import Foundation
import Testing
@testable import CCMaxOKCore

@Suite("UsageResolver JSONL fallback")
struct UsageResolverFallbackTests {

    @Test func todayTokensComeFromJsonlWhenStatsCacheMissing() throws {
        let env = try makeFixture()
        defer { env.cleanup() }

        try env.writeSessionJsonl(
            project: "proj-a",
            session: "s1",
            mtime: env.now,
            lines: [
                .user(sessionId: "s1"),
                .assistant(model: "claude-sonnet-4-5", sessionId: "s1", input: 100, output: 200, cacheRead: 50, cacheCreation: 25)
            ]
        )

        let stats = UsageResolver.computeStats(fileAccess: env.fileAccess, now: env.now)

        #expect(stats.todayTokens == 375)
        #expect(stats.tokenSource == .jsonlFallback)
        #expect(stats.todaySessions == 1)
        #expect(stats.todayMessages == 1)
    }

    @Test func statsCacheTodayEntryWinsOverJsonl() throws {
        let env = try makeFixture()
        defer { env.cleanup() }

        try env.writeSessionJsonl(
            project: "proj-a",
            session: "s1",
            mtime: env.now,
            lines: [
                .assistant(model: "claude-sonnet-4-5", sessionId: "s1", input: 100, output: 200, cacheRead: 0, cacheCreation: 0)
            ]
        )
        try env.writeStatsCache(todayModelTokens: ["claude-sonnet-4-5": 9_999])

        let stats = UsageResolver.computeStats(fileAccess: env.fileAccess, now: env.now)

        #expect(stats.todayTokens == 9_999)
        #expect(stats.tokenSource == .statsCache)
    }

    @Test func statsCachePresentButTodayMissingFallsBackToJsonl() throws {
        let env = try makeFixture()
        defer { env.cleanup() }

        try env.writeSessionJsonl(
            project: "proj-a",
            session: "s1",
            mtime: env.now,
            lines: [
                .assistant(model: "claude-sonnet-4-5", sessionId: "s1", input: 10, output: 20, cacheRead: 0, cacheCreation: 0)
            ]
        )
        // Cache exists but only has yesterday's entry.
        let yesterday = env.dateString(for: env.now.addingTimeInterval(-86_400))
        try env.writeStatsCache(modelTokensByDate: [yesterday: ["claude-sonnet-4-5": 1_000]])

        let stats = UsageResolver.computeStats(fileAccess: env.fileAccess, now: env.now)

        #expect(stats.todayTokens == 30)
        #expect(stats.tokenSource == .jsonlFallback)
    }

    @Test func weekSonnetTokensFallBackToJsonlWhenStatsCacheMissing() throws {
        let env = try makeFixture()
        defer { env.cleanup() }

        // Today: sonnet 100 + opus 999 (opus must NOT count toward sonnet bucket)
        try env.writeSessionJsonl(
            project: "proj-a",
            session: "today",
            mtime: env.now,
            lines: [
                .assistant(model: "claude-sonnet-4-5", sessionId: "today", input: 100, output: 0, cacheRead: 0, cacheCreation: 0),
                .assistant(model: "claude-opus-4-7", sessionId: "today", input: 999, output: 0, cacheRead: 0, cacheCreation: 0)
            ]
        )
        // 3 days ago: sonnet 200
        try env.writeSessionJsonl(
            project: "proj-a",
            session: "older",
            mtime: env.now.addingTimeInterval(-3 * 86_400),
            lines: [
                .assistant(model: "claude-sonnet-4-5", sessionId: "older", input: 200, output: 0, cacheRead: 0, cacheCreation: 0)
            ]
        )
        // 30 days ago: sonnet 9_999 (must NOT count)
        try env.writeSessionJsonl(
            project: "proj-a",
            session: "ancient",
            mtime: env.now.addingTimeInterval(-30 * 86_400),
            lines: [
                .assistant(model: "claude-sonnet-4-5", sessionId: "ancient", input: 9_999, output: 0, cacheRead: 0, cacheCreation: 0)
            ]
        )

        let stats = UsageResolver.computeStats(fileAccess: env.fileAccess, now: env.now)

        #expect(stats.weekSonnetTokens == 300)
    }

    @Test func noJsonlAndNoCacheYieldsZeroAndSourceNone() throws {
        let env = try makeFixture()
        defer { env.cleanup() }

        // projects/ exists but is empty.
        let projects = env.claudeDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        let stats = UsageResolver.computeStats(fileAccess: env.fileAccess, now: env.now)

        #expect(stats.todayTokens == 0)
        #expect(stats.weekSonnetTokens == 0)
        #expect(stats.todaySessions == 0)
        #expect(stats.tokenSource == .none)
    }

    @Test func malformedJsonlLinesAreSkippedAndValidLinesStillCount() throws {
        let env = try makeFixture()
        defer { env.cleanup() }

        // Mix valid + garbage. Malformed lines should be silently dropped, valid usage still summed.
        let valid = ResolverFixture.Line.assistant(
            model: "claude-sonnet-4-5",
            sessionId: "s1",
            input: 50, output: 50, cacheRead: 0, cacheCreation: 0
        ).encoded
        let raw = [
            "this is not json",
            "{\"type\":\"user\",\"sessionId\":\"s1\"}",
            "{\"missing\":\"type field\"}",
            valid,
            "}}{garbage}}"
        ].joined(separator: "\n")

        try env.writeRawSessionJsonl(project: "proj-a", session: "s1", mtime: env.now, raw: raw)

        let stats = UsageResolver.computeStats(fileAccess: env.fileAccess, now: env.now)

        #expect(stats.todayTokens == 100)
        #expect(stats.todayMessages == 1) // only the user line
        #expect(stats.todaySessions == 1)
    }
}

// MARK: - Fixture helpers

private struct ResolverFixture {
    let homeDir: URL
    let claudeDir: URL
    let fileAccess: FileAccessManager
    /// Pinned "current time" for deterministic date arithmetic in tests.
    let now: Date

    func cleanup() {
        try? FileManager.default.removeItem(at: homeDir)
    }

    func dateString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    enum Line {
        case user(sessionId: String)
        case assistant(model: String, sessionId: String, input: Int, output: Int, cacheRead: Int, cacheCreation: Int)

        var encoded: String {
            switch self {
            case .user(let sid):
                return "{\"type\":\"user\",\"sessionId\":\"\(sid)\"}"
            case .assistant(let model, let sid, let input, let output, let cacheRead, let cacheCreation):
                return """
                {"type":"assistant","model":"\(model)","sessionId":"\(sid)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":\(cacheCreation)}}
                """
            }
        }
    }

    func writeSessionJsonl(project: String, session: String, mtime: Date, lines: [Line]) throws {
        let raw = lines.map { $0.encoded }.joined(separator: "\n")
        try writeRawSessionJsonl(project: project, session: session, mtime: mtime, raw: raw)
    }

    func writeRawSessionJsonl(project: String, session: String, mtime: Date, raw: String) throws {
        let projectDir = claudeDir
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("\(session).jsonl")
        try raw.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    }

    func writeStatsCache(todayModelTokens: [String: Int]) throws {
        try writeStatsCache(modelTokensByDate: [dateString(for: now): todayModelTokens])
    }

    func writeStatsCache(modelTokensByDate: [String: [String: Int]]) throws {
        let dailyModelTokens: [[String: Any]] = modelTokensByDate.map { date, tokens in
            ["date": date, "tokensByModel": tokens]
        }
        let dailyActivity: [[String: Any]] = modelTokensByDate.keys.map { date in
            ["date": date, "messageCount": 0, "sessionCount": 0, "toolCallCount": 0]
        }
        let payload: [String: Any] = [
            "lastComputedDate": dateString(for: now),
            "totalSessions": 0,
            "totalMessages": 0,
            "dailyActivity": dailyActivity,
            "dailyModelTokens": dailyModelTokens
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: fileAccess.statsCachePath, options: .atomic)
    }
}

private func makeFixture() throws -> ResolverFixture {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("haru-resolver-test-\(UUID().uuidString)")
    let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
    try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    let fa = FileAccessManager(homeDirectory: home)
    // 모든 케이스에서 파싱 시점은 today 정오 — 자정 경계에서 파일 mtime이 흔들리지 않게.
    var cal = Calendar.current
    cal.timeZone = .current
    let startOfToday = cal.startOfDay(for: Date())
    let noon = startOfToday.addingTimeInterval(12 * 3600)
    return ResolverFixture(homeDir: home, claudeDir: claudeDir, fileAccess: fa, now: noon)
}
