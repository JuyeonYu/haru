import Foundation

/// Single source of truth for "what should the menu bar show right now?".
/// Walks a fallback chain (live JSON → DB snapshot → stats-cache/projects derivation)
/// and records every attempt to `DiagnosticsLogger` so failures are debuggable.
public enum UsageResolver {

    /// DB 스냅샷이 이보다 오래되면 Tier 2를 신뢰할 수 없는 것으로 보고 Tier 3로 내려간다.
    /// 5시간 rate limit 윈도우와 일치 — 그 윈도우가 이미 리셋됐을 가능성이 커서 옛 값은 사용 불가.
    /// (live-status.json이 정상이면 매 응답마다 갱신되므로 이 임계로 인한 사이드 이펙트 미미.)
    public static let staleThreshold: TimeInterval = 5 * 3600

    public struct Snapshot: Sendable, Equatable {
        public enum Freshness: Sendable, Equatable {
            case live
            case stale(asOf: Date)
            case derived(asOf: Date)
        }

        public let freshness: Freshness
        public let fiveHourUsedPct: Double?
        public let fiveHourResetsAt: Date?
        public let sevenDayUsedPct: Double?
        public let sevenDayResetsAt: Date?
        public let todaySessionCount: Int
        public let todayMessageCount: Int
        public let todayTokens: Int
        public let weekSonnetTokens: Int
        public let model: String?

        public var hasRateLimits: Bool {
            fiveHourUsedPct != nil && sevenDayUsedPct != nil
        }
    }

    public enum State: Sendable, Equatable {
        case noClaudeDir
        case waitingFirstRun
        case resolved(Snapshot)
    }

    public struct Stats: Sendable, Equatable {
        public enum TokenSource: String, Sendable, Equatable {
            case statsCache = "stats-cache"
            case jsonlFallback = "jsonl-fallback"
            case none
        }

        public let todaySessions: Int
        public let todayMessages: Int
        public let todayTokens: Int
        public let weekSonnetTokens: Int
        public let latestActivity: Date?
        public let tokenSource: TokenSource
    }

    /// Tier 0(OAuth) 캐시 데이터를 신선하다고 간주할 TTL. OAuthUsageProvider의 캐시 TTL과 정렬.
    public static let oauthCacheTTL: TimeInterval = 5 * 60

    public static func resolve(
        fileAccess: FileAccessManager,
        database: DatabaseManager?,
        oauthCache: OAuthRateLimitsCache? = nil,
        logger: DiagnosticsLogger = .shared,
        now: Date = Date()
    ) -> State {
        guard !fileAccess.allClaudeDirectories.isEmpty else {
            logger.info("resolver", "No Claude config directory found under ~/.claude, ~/.config/claude, or CLAUDE_CONFIG_DIR")
            return .noClaudeDir
        }

        let stats = computeStats(fileAccess: fileAccess, logger: logger)

        // Tier 0: OAuth API 캐시 (statusline 훅과 무관하게 동작 — Claude Code CLI 미실행 시도 데이터 보장).
        if let oauth = oauthCache?.current(now: now, ttl: Self.oauthCacheTTL) {
            let snap = Snapshot(
                freshness: .live,
                fiveHourUsedPct: oauth.fiveHour.usedPercentage,
                fiveHourResetsAt: oauth.fiveHour.resetDate,
                sevenDayUsedPct: oauth.sevenDay.usedPercentage,
                sevenDayResetsAt: oauth.sevenDay.resetDate,
                todaySessionCount: stats.todaySessions,
                todayMessageCount: stats.todayMessages,
                todayTokens: stats.todayTokens,
                weekSonnetTokens: stats.weekSonnetTokens,
                model: nil
            )
            logger.debug("resolver", "Tier 0 (OAuth) resolved")
            return .resolved(snap)
        }

        // Tier 1: live-status.json
        if let payload = tryParseLive(fileAccess: fileAccess, logger: logger) {
            let limits = payload.rateLimits
            if limits == nil {
                logger.info("resolver", "live-status.json has no rateLimits field (plan likely does not expose them)")
            }
            let snap = Snapshot(
                freshness: .live,
                fiveHourUsedPct: limits?.fiveHour.usedPercentage,
                fiveHourResetsAt: limits?.fiveHour.resetDate,
                sevenDayUsedPct: limits?.sevenDay.usedPercentage,
                sevenDayResetsAt: limits?.sevenDay.resetDate,
                todaySessionCount: stats.todaySessions,
                todayMessageCount: stats.todayMessages,
                todayTokens: stats.todayTokens,
                weekSonnetTokens: stats.weekSonnetTokens,
                model: payload.model.id
            )
            logger.debug("resolver", "Tier 1 (live) resolved — limits=\(limits != nil ? "yes" : "no")")
            return .resolved(snap)
        }

        // Tier 2: DB last snapshot
        if let db = database {
            // Tier 1이 실패해서 여기까지 온 상태에서도, live-status.json 자체는 디스크에 더 새로운
            // mtime으로 존재할 수 있다(파싱만 실패한 케이스). 그 경우 옛 DB 값을 띄우면 사용자가
            // 실제와 다른 잔여량을 보게 되므로 mtime을 비교해 live가 더 새로우면 Tier 2를 스킵한다.
            let liveMod = (try? FileManager.default.attributesOfItem(atPath: fileAccess.liveStatusPath.path)[.modificationDate]) as? Date
            do {
                if let row = try db.rateLimitSnapshots(last: 1).first {
                    let snapshotDate = Date(timeIntervalSince1970: row.timestamp)
                    let age = now.timeIntervalSince(snapshotDate)
                    if age > Self.staleThreshold {
                        logger.info("resolver", "Tier 2 skipped — snapshot is \(Int(age / 3600))h old, beyond \(Int(Self.staleThreshold / 3600))h threshold")
                    } else if let liveMod, liveMod > snapshotDate {
                        logger.info("resolver", "Tier 2 skipped — live-status.json (mtime \(liveMod)) is newer than DB snapshot (\(snapshotDate)); Tier 1 parse failure should not surface stale DB")
                    } else {
                        let snap = Snapshot(
                            freshness: .stale(asOf: snapshotDate),
                            fiveHourUsedPct: row.fiveHourUsedPct,
                            fiveHourResetsAt: row.fiveHourResetsAt.map { Date(timeIntervalSince1970: $0) },
                            sevenDayUsedPct: row.sevenDayUsedPct,
                            sevenDayResetsAt: row.sevenDayResetsAt.map { Date(timeIntervalSince1970: $0) },
                            todaySessionCount: stats.todaySessions,
                            todayMessageCount: stats.todayMessages,
                            todayTokens: stats.todayTokens,
                            weekSonnetTokens: stats.weekSonnetTokens,
                            model: row.model
                        )
                        logger.info("resolver", "Tier 2 (stale) resolved from DB snapshot dated \(snapshotDate)")
                        return .resolved(snap)
                    }
                } else {
                    logger.info("resolver", "Tier 2 has no rows in rate_limit_snapshots")
                }
            } catch {
                logger.warn("resolver", "Tier 2 DB query failed", error: error)
            }
        } else {
            logger.warn("resolver", "Tier 2 skipped — database is nil")
        }

        // Tier 3: derived from stats-cache.json / session jsonl
        if stats.todayTokens > 0 || stats.todaySessions > 0 || stats.weekSonnetTokens > 0 {
            let asOf = stats.latestActivity ?? now
            let snap = Snapshot(
                freshness: .derived(asOf: asOf),
                fiveHourUsedPct: nil,
                fiveHourResetsAt: nil,
                sevenDayUsedPct: nil,
                sevenDayResetsAt: nil,
                todaySessionCount: stats.todaySessions,
                todayMessageCount: stats.todayMessages,
                todayTokens: stats.todayTokens,
                weekSonnetTokens: stats.weekSonnetTokens,
                model: nil
            )
            logger.info("resolver", "Tier 3 (derived) resolved — tokens=\(stats.todayTokens) (source: \(stats.tokenSource.rawValue)), sessions=\(stats.todaySessions)")
            return .resolved(snap)
        }

        logger.warn("resolver", "All tiers exhausted — entering waitingFirstRun")
        return .waitingFirstRun
    }

    // MARK: - Helpers

    private static func tryParseLive(
        fileAccess: FileAccessManager,
        logger: DiagnosticsLogger
    ) -> StatuslinePayload? {
        let url = fileAccess.liveStatusPath
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.info("resolver", "Tier 1 skipped — \(url.path) does not exist")
            return nil
        }
        do {
            return try UsageParser.parseStatuslinePayload(at: url)
        } catch {
            logger.warn("resolver", "Tier 1 failed to parse live-status.json at \(url.path)", error: error)
            return nil
        }
    }

    public static func computeStats(
        fileAccess: FileAccessManager,
        logger: DiagnosticsLogger = .shared,
        now: Date = Date()
    ) -> Stats {
        let cache = tryParseStatsCache(fileAccess: fileAccess, logger: logger)

        // 날짜 경계는 시스템 로컬 타임존 기준. 명시적으로 설정해 테스트·코드 리뷰에서 의도를 드러낸다.
        var calendar = Calendar.current
        calendar.timeZone = .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = fmt.string(from: now)

        let sessionInfo = scanSessionFiles(fileAccess: fileAccess, now: now, logger: logger)

        // stats-cache.json이 today 엔트리를 갖고 있을 때만 그 값을 신뢰. 없으면 JSONL 합산으로 폴백.
        // (의도된 부분 집계를 덮어쓰지 않도록 "없음"과 "0"을 구분.)
        let cacheTodayTokens: Int? = cache?.modelTokens(for: todayStr).map { $0.values.reduce(0, +) }
        let todayTokens: Int
        let tokenSource: Stats.TokenSource
        if let cached = cacheTodayTokens {
            todayTokens = cached
            tokenSource = .statsCache
        } else if sessionInfo.todayTokens > 0 {
            todayTokens = sessionInfo.todayTokens
            tokenSource = .jsonlFallback
        } else {
            todayTokens = 0
            tokenSource = .none
        }

        let weekSonnetTokens: Int
        if let cache {
            var sonnetTotal = 0
            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                let dateStr = fmt.string(from: date)
                if let modelTokens = cache.modelTokens(for: dateStr) {
                    for (model, tokens) in modelTokens where model.lowercased().contains("sonnet") {
                        sonnetTotal += tokens
                    }
                }
            }
            weekSonnetTokens = sonnetTotal
        } else {
            weekSonnetTokens = sessionInfo.weekSonnetTokens
        }

        return Stats(
            todaySessions: sessionInfo.sessions,
            todayMessages: sessionInfo.messages,
            todayTokens: todayTokens,
            weekSonnetTokens: weekSonnetTokens,
            latestActivity: sessionInfo.latestMod,
            tokenSource: tokenSource
        )
    }

    private static func tryParseStatsCache(
        fileAccess: FileAccessManager,
        logger: DiagnosticsLogger
    ) -> StatsCache? {
        let url = fileAccess.statsCachePath
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.debug("resolver", "stats-cache.json not present at \(url.path)")
            return nil
        }
        do {
            return try UsageParser.parseStatsCache(at: url)
        } catch {
            logger.warn("resolver", "Failed to parse stats-cache.json", error: error)
            return nil
        }
    }

    private struct SessionScan {
        let sessions: Int
        let messages: Int
        let latestMod: Date?
        /// stats-cache.json이 today 엔트리를 제공하지 못할 때 사용할 JSONL 합산값.
        let todayTokens: Int
        /// stats-cache.json이 아예 없을 때 사용할 JSONL 7일치 Sonnet 합산값.
        let weekSonnetTokens: Int
    }

    private static func scanSessionFiles(
        fileAccess: FileAccessManager,
        now: Date,
        logger: DiagnosticsLogger
    ) -> SessionScan {
        let fm = FileManager.default
        var calendar = Calendar.current
        calendar.timeZone = .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = fmt.string(from: now)

        // 주간 Sonnet 계산용 윈도우: today 포함 7일 전 00:00부터.
        // (stats-cache의 `0..<7` dayOffset 범위와 일치시켜 동일 의미 유지.)
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        do {
            let files = try fileAccess.sessionFiles()
            var sessions = 0
            var messages = 0
            var todayTokens = 0
            var weekSonnet = 0
            var latest: Date?
            // 같은 message_id+request_id가 여러 jsonl(fork된 세션 등)에 재기록되는 케이스에서
            // 토큰을 중복 합산하지 않도록 전역 dedup 키. ai-token-monitor와 동일한 전략.
            var seenAssistantKeys = Set<String>()

            for url in files {
                let attrs = try fm.attributesOfItem(atPath: url.path)
                guard let mod = attrs[.modificationDate] as? Date else { continue }
                if latest == nil || mod > latest! { latest = mod }

                let isToday = fmt.string(from: mod) == todayStr
                let inWeekWindow = mod >= weekStart
                // 7일 이전 파일은 파싱 비용 회피(팝오버 갱신 30초 주기에서 수백 파일 × MB 방어).
                guard isToday || inWeekWindow else { continue }

                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let msgs = SessionMessage.parseJSONL(content, context: url.lastPathComponent)

                if isToday {
                    sessions += 1
                    messages += msgs.filter { $0.type == "user" }.count
                }

                for m in msgs {
                    guard m.type == "assistant", let usage = m.usage else { continue }
                    let dedupKey: String? = {
                        guard let mid = m.messageId else { return nil }
                        return "\(mid):\(m.requestId ?? "")"
                    }()
                    if let key = dedupKey {
                        if seenAssistantKeys.contains(key) { continue }
                        seenAssistantKeys.insert(key)
                    }

                    let totalTokens = usage.inputTokens
                        + usage.outputTokens
                        + (usage.cacheReadInputTokens ?? 0)
                        + (usage.cacheCreationInputTokens ?? 0)

                    if isToday {
                        todayTokens += totalTokens
                    }
                    if inWeekWindow,
                       let model = m.model,
                       model.lowercased().contains("sonnet") {
                        weekSonnet += totalTokens
                    }
                }
            }
            return SessionScan(
                sessions: sessions,
                messages: messages,
                latestMod: latest,
                todayTokens: todayTokens,
                weekSonnetTokens: weekSonnet
            )
        } catch {
            logger.warn("resolver", "Failed to enumerate session jsonl files", error: error)
            return SessionScan(sessions: 0, messages: 0, latestMod: nil, todayTokens: 0, weekSonnetTokens: 0)
        }
    }
}
