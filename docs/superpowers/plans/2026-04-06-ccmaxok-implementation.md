# CCMaxOK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that monitors Claude Code token usage, sends push notifications for overuse/waste, and recommends smart token utilization with Max vs Pro plan comparison.

**Architecture:** Core business logic lives in a Swift Package (`CCMaxOKCore`) for testability with `swift test`. The Xcode app project is a thin shell that imports the package and provides the SwiftUI menu bar UI. Data flows from Claude Code's statusline API and local files → FileWatcher → UsageAnalyzer → UI/Notifications.

**Tech Stack:** Swift 6, SwiftUI, macOS 15+, SQLite (via swift-sqlite directly, no heavy ORM), XCTest

---

## File Structure

```
CCMaxOK/
├── Package.swift                              -- SPM package for core logic
├── Sources/
│   └── CCMaxOKCore/
│       ├── Models/
│       │   ├── RateLimitStatus.swift           -- Codable model for statusline rate_limits
│       │   ├── StatuslinePayload.swift         -- Full statusline JSON model
│       │   ├── DailyUsage.swift                -- Daily usage aggregate model
│       │   ├── StatsCache.swift                -- stats-cache.json Codable model
│       │   ├── SessionMessage.swift            -- JSONL session message model
│       │   └── Recommendation.swift            -- Recommendation type + factory
│       ├── Services/
│       │   ├── DatabaseManager.swift           -- SQLite schema + CRUD
│       │   ├── FileAccessManager.swift         -- Path resolution, sandbox bookmark abstraction
│       │   ├── UsageParser.swift               -- Parse stats-cache.json + JSONL files
│       │   ├── StatuslineSetup.swift           -- Deploy statusline.sh, patch settings.json
│       │   ├── FileWatcher.swift               -- FSEvents (foreground) + Timer (background)
│       │   ├── UsageAnalyzer.swift             -- Trend analysis, recommendations, plan comparison
│       │   └── NotificationManager.swift       -- macOS UserNotifications + cooldown
│       └── Resources/
│           └── statusline.sh                   -- Statusline script template
├── Tests/
│   └── CCMaxOKCoreTests/
│       ├── Models/
│       │   ├── RateLimitStatusTests.swift
│       │   ├── StatuslinePayloadTests.swift
│       │   ├── DailyUsageTests.swift
│       │   ├── StatsCacheTests.swift
│       │   ├── SessionMessageTests.swift
│       │   └── RecommendationTests.swift
│       ├── Services/
│       │   ├── DatabaseManagerTests.swift
│       │   ├── FileAccessManagerTests.swift
│       │   ├── UsageParserTests.swift
│       │   ├── StatuslineSetupTests.swift
│       │   ├── UsageAnalyzerTests.swift
│       │   └── NotificationManagerTests.swift
│       └── Fixtures/
│           ├── sample-statusline.json
│           ├── sample-stats-cache.json
│           └── sample-session.jsonl
├── CCMaxOKApp/
│   ├── CCMaxOKApp.swift                        -- @main, MenuBarExtra
│   ├── AppState.swift                          -- ObservableObject wiring all services
│   ├── Views/
│   │   ├── MenuBarView.swift                   -- Popover container
│   │   ├── RateLimitCard.swift                 -- Rate limit progress bars
│   │   ├── TodayStatsCard.swift                -- Today's stats
│   │   ├── RecommendationCard.swift            -- Smart tip card
│   │   ├── PlanInsightCard.swift               -- Max vs Pro insight
│   │   └── SettingsView.swift                  -- Notification threshold settings
│   ├── CCMaxOKApp.entitlements                 -- App Sandbox + network (future)
│   └── Resources/
│       └── PrivacyInfo.xcprivacy               -- Privacy manifest
└── docs/
    └── superpowers/
        ├── specs/
        │   └── 2026-04-06-ccmaxok-design.md
        └── plans/
            └── 2026-04-06-ccmaxok-implementation.md
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/CCMaxOKCore/CCMaxOKCore.swift` (namespace placeholder)
- Create: `Tests/CCMaxOKCoreTests/CCMaxOKCoreTests.swift` (smoke test)
- Create: `.gitignore`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
xcuserdata/

# Swift Package Manager
.build/
.swiftpm/
Package.resolved

# macOS
.DS_Store
*.swp
*~

# Superpowers
.superpowers/
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCMaxOK",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CCMaxOKCore", targets: ["CCMaxOKCore"])
    ],
    targets: [
        .target(
            name: "CCMaxOKCore",
            resources: [.copy("Resources/statusline.sh")]
        ),
        .testTarget(
            name: "CCMaxOKCoreTests",
            dependencies: ["CCMaxOKCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 3: Create namespace placeholder**

Create `Sources/CCMaxOKCore/CCMaxOKCore.swift`:

```swift
/// CCMaxOKCore — Core logic for Claude Code usage monitoring.
public enum CCMaxOKCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Create the statusline script resource**

Create `Sources/CCMaxOKCore/Resources/statusline.sh`:

```bash
#!/bin/bash
cat /dev/stdin > ~/.claude/ccmaxok/live-status.json
```

- [ ] **Step 5: Create smoke test**

Create `Tests/CCMaxOKCoreTests/CCMaxOKCoreTests.swift`:

```swift
import Testing
@testable import CCMaxOKCore

@Test func versionExists() {
    #expect(CCMaxOKCore.version == "0.1.0")
}
```

- [ ] **Step 6: Run test to verify setup works**

Run: `cd /Users/yujuyeon/Dev/jp/mcp_projects/ccmaxok && swift test`
Expected: All tests pass. 1 test, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ Tests/ .gitignore
git commit -m "chore: scaffold Swift package with core library and test target"
```

---

### Task 2: Test Fixtures

**Files:**
- Create: `Tests/CCMaxOKCoreTests/Fixtures/sample-statusline.json`
- Create: `Tests/CCMaxOKCoreTests/Fixtures/sample-stats-cache.json`
- Create: `Tests/CCMaxOKCoreTests/Fixtures/sample-session.jsonl`

- [ ] **Step 1: Create sample statusline JSON**

Create `Tests/CCMaxOKCoreTests/Fixtures/sample-statusline.json`:

```json
{
  "session_id": "abc123",
  "model": {
    "id": "claude-opus-4-6",
    "display_name": "Claude Opus 4.6"
  },
  "cost": {
    "total_cost_usd": 0.0,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 32000,
    "total_lines_added": 150,
    "total_lines_removed": 30
  },
  "context_window": {
    "total_input_tokens": 25000,
    "total_output_tokens": 5000,
    "used_percentage": 15.0,
    "current_usage": {
      "input_tokens": 3000,
      "output_tokens": 500,
      "cache_read_input_tokens": 12000,
      "cache_creation_input_tokens": 5000
    },
    "context_window_size": 200000
  },
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42.0,
      "resets_at": 1775470000
    },
    "seven_day": {
      "used_percentage": 28.0,
      "resets_at": 1775900000
    }
  }
}
```

- [ ] **Step 2: Create sample stats-cache JSON**

Create `Tests/CCMaxOKCoreTests/Fixtures/sample-stats-cache.json`:

```json
{
  "lastComputedDate": "2026-04-06",
  "totalSessions": 250,
  "totalMessages": 8500,
  "dailyActivity": {
    "2026-04-05": { "messageCount": 120, "sessionCount": 8, "toolCallCount": 45 },
    "2026-04-06": { "messageCount": 85, "sessionCount": 5, "toolCallCount": 30 }
  },
  "dailyModelTokens": {
    "2026-04-05": { "claude-opus-4-6": 350000, "claude-haiku-4-5-20251001": 12000 },
    "2026-04-06": { "claude-opus-4-6": 180000 }
  },
  "modelUsage": {
    "claude-opus-4-6": {
      "inputTokens": 5000000,
      "outputTokens": 1200000,
      "cacheReadInputTokens": 3000000,
      "cacheCreationInputTokens": 800000,
      "costUSD": 0.0
    }
  },
  "hourCounts": {
    "14": 250, "15": 300, "16": 280, "17": 200,
    "10": 50, "11": 80, "9": 30
  }
}
```

- [ ] **Step 3: Create sample session JSONL**

Create `Tests/CCMaxOKCoreTests/Fixtures/sample-session.jsonl`:

```jsonl
{"type":"user","timestamp":"2026-04-06T10:00:00Z","sessionId":"sess1","message":"Fix the login bug"}
{"type":"assistant","timestamp":"2026-04-06T10:00:05Z","sessionId":"sess1","model":"claude-opus-4-6","usage":{"input_tokens":3000,"output_tokens":500,"cache_read_input_tokens":1200,"cache_creation_input_tokens":800},"message":"I'll fix the login bug."}
{"type":"user","timestamp":"2026-04-06T10:01:00Z","sessionId":"sess1","message":"Now add tests"}
{"type":"assistant","timestamp":"2026-04-06T10:01:08Z","sessionId":"sess1","model":"claude-opus-4-6","usage":{"input_tokens":4500,"output_tokens":1200,"cache_read_input_tokens":2000,"cache_creation_input_tokens":500},"message":"Adding tests now."}
```

- [ ] **Step 4: Verify fixtures load**

Run: `swift test`
Expected: Still passes (fixtures exist but aren't used yet).

- [ ] **Step 5: Commit**

```bash
git add Tests/CCMaxOKCoreTests/Fixtures/
git commit -m "test: add fixture files for statusline, stats-cache, and session JSONL"
```

---

### Task 3: Data Models — StatuslinePayload & RateLimitStatus

**Files:**
- Create: `Sources/CCMaxOKCore/Models/RateLimitStatus.swift`
- Create: `Sources/CCMaxOKCore/Models/StatuslinePayload.swift`
- Create: `Tests/CCMaxOKCoreTests/Models/StatuslinePayloadTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Models/StatuslinePayloadTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func decodesStatuslinePayload() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-statusline", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let payload = try JSONDecoder().decode(StatuslinePayload.self, from: data)

    #expect(payload.sessionId == "abc123")
    #expect(payload.model.id == "claude-opus-4-6")
    #expect(payload.rateLimits?.fiveHour.usedPercentage == 42.0)
    #expect(payload.rateLimits?.sevenDay.usedPercentage == 28.0)
    #expect(payload.rateLimits?.fiveHour.resetsAt == 1775470000)
    #expect(payload.cost.totalCostUsd == 0.0)
    #expect(payload.contextWindow.totalInputTokens == 25000)
}

@Test func rateLimitStatusColor() {
    let green = RateLimitWindow(usedPercentage: 30.0, resetsAt: 0)
    let yellow = RateLimitWindow(usedPercentage: 70.0, resetsAt: 0)
    let red = RateLimitWindow(usedPercentage: 85.0, resetsAt: 0)

    #expect(green.alertLevel == .normal)
    #expect(yellow.alertLevel == .warning)
    #expect(red.alertLevel == .critical)
}

@Test func rateLimitTimeUntilReset() {
    let futureReset = Date().timeIntervalSince1970 + 3600  // 1 hour from now
    let window = RateLimitWindow(usedPercentage: 50.0, resetsAt: futureReset)
    let remaining = window.timeUntilReset

    // Should be roughly 3600 seconds (allow 5s tolerance for test execution)
    #expect(remaining > 3590)
    #expect(remaining <= 3600)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatuslinePayload`
Expected: FAIL — `StatuslinePayload` not found.

- [ ] **Step 3: Create RateLimitStatus model**

Create `Sources/CCMaxOKCore/Models/RateLimitStatus.swift`:

```swift
import Foundation

public enum AlertLevel: Sendable {
    case normal    // 0-60%
    case warning   // 60-80%
    case critical  // 80%+
}

public struct RateLimitWindow: Codable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Double

    public var alertLevel: AlertLevel {
        if usedPercentage >= 80 { return .critical }
        if usedPercentage >= 60 { return .warning }
        return .normal
    }

    public var timeUntilReset: TimeInterval {
        max(0, resetsAt - Date().timeIntervalSince1970)
    }

    public var resetDate: Date {
        Date(timeIntervalSince1970: resetsAt)
    }

    public var remainingPercentage: Double {
        max(0, 100.0 - usedPercentage)
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

public struct RateLimits: Codable, Sendable {
    public let fiveHour: RateLimitWindow
    public let sevenDay: RateLimitWindow

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
```

- [ ] **Step 4: Create StatuslinePayload model**

Create `Sources/CCMaxOKCore/Models/StatuslinePayload.swift`:

```swift
import Foundation

public struct StatuslineModel: Codable, Sendable {
    public let id: String
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct StatuslineCost: Codable, Sendable {
    public let totalCostUsd: Double
    public let totalDurationMs: Int
    public let totalApiDurationMs: Int
    public let totalLinesAdded: Int
    public let totalLinesRemoved: Int

    enum CodingKeys: String, CodingKey {
        case totalCostUsd = "total_cost_usd"
        case totalDurationMs = "total_duration_ms"
        case totalApiDurationMs = "total_api_duration_ms"
        case totalLinesAdded = "total_lines_added"
        case totalLinesRemoved = "total_lines_removed"
    }
}

public struct ContextWindowUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

public struct ContextWindow: Codable, Sendable {
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let usedPercentage: Double
    public let currentUsage: ContextWindowUsage
    public let contextWindowSize: Int

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case usedPercentage = "used_percentage"
        case currentUsage = "current_usage"
        case contextWindowSize = "context_window_size"
    }
}

public struct StatuslinePayload: Codable, Sendable {
    public let sessionId: String
    public let model: StatuslineModel
    public let cost: StatuslineCost
    public let contextWindow: ContextWindow
    public let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case model
        case cost
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter StatuslinePayload`
Expected: PASS — all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCMaxOKCore/Models/RateLimitStatus.swift Sources/CCMaxOKCore/Models/StatuslinePayload.swift Tests/CCMaxOKCoreTests/Models/StatuslinePayloadTests.swift
git commit -m "feat: add StatuslinePayload and RateLimitStatus models with decoding"
```

---

### Task 4: Data Models — StatsCache & SessionMessage

**Files:**
- Create: `Sources/CCMaxOKCore/Models/StatsCache.swift`
- Create: `Sources/CCMaxOKCore/Models/SessionMessage.swift`
- Create: `Sources/CCMaxOKCore/Models/DailyUsage.swift`
- Create: `Tests/CCMaxOKCoreTests/Models/StatsCacheTests.swift`
- Create: `Tests/CCMaxOKCoreTests/Models/SessionMessageTests.swift`

- [ ] **Step 1: Write failing tests for StatsCache**

Create `Tests/CCMaxOKCoreTests/Models/StatsCacheTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func decodesStatsCache() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let cache = try JSONDecoder().decode(StatsCache.self, from: data)

    #expect(cache.totalSessions == 250)
    #expect(cache.totalMessages == 8500)
    #expect(cache.dailyActivity.count == 2)
    #expect(cache.dailyActivity["2026-04-05"]?.messageCount == 120)
    #expect(cache.dailyModelTokens["2026-04-06"]?["claude-opus-4-6"] == 180000)
    #expect(cache.hourCounts["14"] == 250)
}

@Test func statsCachePeakHours() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let cache = try JSONDecoder().decode(StatsCache.self, from: data)

    let peak = cache.peakHours(top: 3)
    #expect(peak.count == 3)
    #expect(peak[0].hour == "15")  // 300 is highest
}
```

- [ ] **Step 2: Write failing tests for SessionMessage**

Create `Tests/CCMaxOKCoreTests/Models/SessionMessageTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func decodesSessionMessages() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-session", withExtension: "jsonl")!
    let content = try String(contentsOf: url, encoding: .utf8)
    let messages = SessionMessage.parseJSONL(content)

    #expect(messages.count == 4)

    let assistantMessages = messages.filter { $0.type == "assistant" }
    #expect(assistantMessages.count == 2)
    #expect(assistantMessages[0].usage?.inputTokens == 3000)
    #expect(assistantMessages[0].usage?.outputTokens == 500)
    #expect(assistantMessages[0].model == "claude-opus-4-6")
}

@Test func sessionMessageTotalTokens() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-session", withExtension: "jsonl")!
    let content = try String(contentsOf: url, encoding: .utf8)
    let messages = SessionMessage.parseJSONL(content)
    let assistantMessages = messages.filter { $0.type == "assistant" }

    let total = SessionMessage.totalTokens(assistantMessages)
    // msg1: 3000+500+1200+800 = 5500, msg2: 4500+1200+2000+500 = 8200
    #expect(total.input == 7500)
    #expect(total.output == 1700)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter "StatsCache|SessionMessage"`
Expected: FAIL — types not found.

- [ ] **Step 4: Create StatsCache model**

Create `Sources/CCMaxOKCore/Models/StatsCache.swift`:

```swift
import Foundation

public struct DailyActivity: Codable, Sendable {
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int
}

public struct ModelUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int
    public let costUSD: Double
}

public struct StatsCache: Codable, Sendable {
    public let lastComputedDate: String?
    public let totalSessions: Int
    public let totalMessages: Int
    public let dailyActivity: [String: DailyActivity]
    public let dailyModelTokens: [String: [String: Int]]
    public let modelUsage: [String: ModelUsage]?
    public let hourCounts: [String: Int]?

    public struct HourCount: Sendable {
        public let hour: String
        public let count: Int
    }

    public func peakHours(top n: Int) -> [HourCount] {
        guard let hourCounts else { return [] }
        return hourCounts
            .map { HourCount(hour: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(n)
            .map { $0 }
    }
}
```

- [ ] **Step 5: Create SessionMessage model**

Create `Sources/CCMaxOKCore/Models/SessionMessage.swift`:

```swift
import Foundation

public struct MessageUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int?
    public let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

public struct SessionMessage: Codable, Sendable {
    public let type: String
    public let timestamp: String
    public let sessionId: String
    public let model: String?
    public let usage: MessageUsage?
    public let message: String?

    public struct TokenTotals: Sendable {
        public let input: Int
        public let output: Int
        public let cacheRead: Int
        public let cacheCreation: Int

        public var total: Int { input + output + cacheRead + cacheCreation }
    }

    public static func parseJSONL(_ content: String) -> [SessionMessage] {
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionMessage.self, from: data)
            }
    }

    public static func totalTokens(_ messages: [SessionMessage]) -> TokenTotals {
        var input = 0, output = 0, cacheRead = 0, cacheCreation = 0
        for msg in messages {
            guard let usage = msg.usage else { continue }
            input += usage.inputTokens
            output += usage.outputTokens
            cacheRead += usage.cacheReadInputTokens ?? 0
            cacheCreation += usage.cacheCreationInputTokens ?? 0
        }
        return TokenTotals(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
    }
}
```

- [ ] **Step 6: Create DailyUsage model**

Create `Sources/CCMaxOKCore/Models/DailyUsage.swift`:

```swift
import Foundation

public struct DailyUsage: Sendable {
    public let date: String
    public let sessionCount: Int
    public let messageCount: Int
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCacheReadTokens: Int
    public let totalCacheCreationTokens: Int
    public let modelsUsed: [String]

    public var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheReadTokens + totalCacheCreationTokens
    }

    public init(date: String, sessionCount: Int = 0, messageCount: Int = 0,
                totalInputTokens: Int = 0, totalOutputTokens: Int = 0,
                totalCacheReadTokens: Int = 0, totalCacheCreationTokens: Int = 0,
                modelsUsed: [String] = []) {
        self.date = date
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCacheReadTokens = totalCacheReadTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.modelsUsed = modelsUsed
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter "StatsCache|SessionMessage"`
Expected: PASS — all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/CCMaxOKCore/Models/ Tests/CCMaxOKCoreTests/Models/
git commit -m "feat: add StatsCache, SessionMessage, and DailyUsage models"
```

---

### Task 5: Data Models — Recommendation

**Files:**
- Create: `Sources/CCMaxOKCore/Models/Recommendation.swift`
- Create: `Tests/CCMaxOKCoreTests/Models/RecommendationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Models/RecommendationTests.swift`:

```swift
import Testing
@testable import CCMaxOKCore

@Test func tokenBasedRecommendationHigh() {
    let rec = Recommendation.forRemainingCapacity(
        remainingPercentage: 65.0,
        hoursUntilReset: 3.0
    )
    #expect(rec.category == .highCapacity)
    #expect(!rec.message.isEmpty)
    #expect(!rec.suggestions.isEmpty)
}

@Test func tokenBasedRecommendationMedium() {
    let rec = Recommendation.forRemainingCapacity(
        remainingPercentage: 35.0,
        hoursUntilReset: 2.0
    )
    #expect(rec.category == .mediumCapacity)
}

@Test func tokenBasedRecommendationLow() {
    let rec = Recommendation.forRemainingCapacity(
        remainingPercentage: 10.0,
        hoursUntilReset: 1.0
    )
    #expect(rec.category == .lowCapacity)
}

@Test func planInsightRecommendsProWhenLowUsage() {
    let insight = PlanInsight.evaluate(
        proExceedDays: 2,
        totalDays: 30,
        averageDailyUsagePercent: 15.0
    )
    #expect(insight.recommendation == .switchToPro)
}

@Test func planInsightRecommendsMaxWhenHighUsage() {
    let insight = PlanInsight.evaluate(
        proExceedDays: 15,
        totalDays: 30,
        averageDailyUsagePercent: 70.0
    )
    #expect(insight.recommendation == .keepMax)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Recommendation`
Expected: FAIL — `Recommendation` not found.

- [ ] **Step 3: Create Recommendation model**

Create `Sources/CCMaxOKCore/Models/Recommendation.swift`:

```swift
import Foundation

public enum CapacityCategory: Sendable {
    case highCapacity   // >50% remaining
    case mediumCapacity // 20-50% remaining
    case lowCapacity    // <20% remaining
}

public struct Recommendation: Sendable {
    public let category: CapacityCategory
    public let message: String
    public let suggestions: [String]

    public static func forRemainingCapacity(
        remainingPercentage: Double,
        hoursUntilReset: Double
    ) -> Recommendation {
        if remainingPercentage > 50 {
            return Recommendation(
                category: .highCapacity,
                message: "여유가 많아요! 큰 작업을 하기 좋은 때예요.",
                suggestions: [
                    "프로젝트 리팩토링",
                    "테스트 커버리지 올리기",
                    "코드 문서화"
                ]
            )
        } else if remainingPercentage > 20 {
            return Recommendation(
                category: .mediumCapacity,
                message: "적당히 남았어요. 중간 규모 작업에 활용하세요.",
                suggestions: [
                    "코드 리뷰",
                    "버그 수정",
                    "유닛 테스트 추가"
                ]
            )
        } else {
            return Recommendation(
                category: .lowCapacity,
                message: "한도가 얼마 안 남았어요. 가볍게 사용하세요.",
                suggestions: [
                    "짧은 질문",
                    "문서 검토",
                    "간단한 수정"
                ]
            )
        }
    }
}

public enum PlanRecommendation: Sendable {
    case keepMax
    case switchToPro
}

public struct PlanInsight: Sendable {
    public let recommendation: PlanRecommendation
    public let proExceedDays: Int
    public let totalDays: Int
    public let averageDailyUsagePercent: Double
    public let summary: String

    public static func evaluate(
        proExceedDays: Int,
        totalDays: Int,
        averageDailyUsagePercent: Double
    ) -> PlanInsight {
        let shouldSwitchToPro = proExceedDays <= 5 && averageDailyUsagePercent < 40.0

        let recommendation: PlanRecommendation = shouldSwitchToPro ? .switchToPro : .keepMax

        let summary: String
        if shouldSwitchToPro {
            summary = "지난 \(totalDays)일 중 Pro 한도 초과일: \(proExceedDays)일. Pro 전환을 고려해보세요."
        } else {
            summary = "지난 \(totalDays)일 중 Pro 한도 초과일: \(proExceedDays)일. Max 유지를 추천합니다."
        }

        return PlanInsight(
            recommendation: recommendation,
            proExceedDays: proExceedDays,
            totalDays: totalDays,
            averageDailyUsagePercent: averageDailyUsagePercent,
            summary: summary
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter Recommendation`
Expected: PASS — all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Models/Recommendation.swift Tests/CCMaxOKCoreTests/Models/RecommendationTests.swift
git commit -m "feat: add Recommendation and PlanInsight models"
```

---

### Task 6: DatabaseManager — SQLite Setup & CRUD

**Files:**
- Create: `Sources/CCMaxOKCore/Services/DatabaseManager.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/DatabaseManagerTests.swift`

- [ ] **Step 1: Add SQLite dependency to Package.swift**

Update `Package.swift` — add the sqlite3 system library. Since we're on macOS, `libsqlite3` is available system-wide. We'll use it via a thin C-interop wrapper.

Replace the entire `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCMaxOK",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CCMaxOKCore", targets: ["CCMaxOKCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .target(
            name: "CCMaxOKCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            resources: [.copy("Resources/statusline.sh")]
        ),
        .testTarget(
            name: "CCMaxOKCoreTests",
            dependencies: ["CCMaxOKCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/DatabaseManagerTests.swift`:

```swift
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

    // Should not throw — tables exist
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter DatabaseManager`
Expected: FAIL — `DatabaseManager` not found.

- [ ] **Step 4: Create DatabaseManager**

Create `Sources/CCMaxOKCore/Services/DatabaseManager.swift`:

```swift
import Foundation
import SQLite

public final class DatabaseManager: Sendable {
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter DatabaseManager`
Expected: PASS — all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/CCMaxOKCore/Services/DatabaseManager.swift Tests/CCMaxOKCoreTests/Services/DatabaseManagerTests.swift
git commit -m "feat: add DatabaseManager with SQLite schema and CRUD operations"
```

---

### Task 7: FileAccessManager

**Files:**
- Create: `Sources/CCMaxOKCore/Services/FileAccessManager.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/FileAccessManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/FileAccessManagerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileAccessManager`
Expected: FAIL — `FileAccessManager` not found.

- [ ] **Step 3: Create FileAccessManager**

Create `Sources/CCMaxOKCore/Services/FileAccessManager.swift`:

```swift
import Foundation

public final class FileAccessManager: Sendable {
    private let homeDirectory: URL

    public init(homeDirectory: URL? = nil) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public var claudeDirectory: URL {
        homeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    public var ccmaxokDirectory: URL {
        claudeDirectory.appendingPathComponent("ccmaxok", isDirectory: true)
    }

    public var liveStatusPath: URL {
        ccmaxokDirectory.appendingPathComponent("live-status.json")
    }

    public var statsCachePath: URL {
        claudeDirectory.appendingPathComponent("stats-cache.json")
    }

    public var settingsPath: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    public var statuslineScriptPath: URL {
        ccmaxokDirectory.appendingPathComponent("statusline.sh")
    }

    public var databasePath: URL {
        ccmaxokDirectory.appendingPathComponent("history.sqlite")
    }

    public var projectsDirectory: URL {
        claudeDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    public func ensureCCMaxOKDirectory() throws {
        try FileManager.default.createDirectory(
            at: ccmaxokDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Find all .jsonl session files under ~/.claude/projects/
    public func sessionFiles() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDirectory.path()) else { return [] }

        var jsonlFiles: [URL] = []
        if let enumerator = fm.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "jsonl" {
                    jsonlFiles.append(fileURL)
                }
            }
        }
        return jsonlFiles
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileAccessManager`
Expected: PASS — all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Services/FileAccessManager.swift Tests/CCMaxOKCoreTests/Services/FileAccessManagerTests.swift
git commit -m "feat: add FileAccessManager for path resolution and sandbox abstraction"
```

---

### Task 8: UsageParser — Parse stats-cache.json and JSONL

**Files:**
- Create: `Sources/CCMaxOKCore/Services/UsageParser.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/UsageParserTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/UsageParserTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func parsesStatsCache() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let cache = try UsageParser.parseStatsCache(at: url)

    #expect(cache.totalSessions == 250)
    #expect(cache.dailyActivity.count == 2)
}

@Test func parsesStatuslinePayload() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-statusline", withExtension: "json")!
    let payload = try UsageParser.parseStatuslinePayload(at: url)

    #expect(payload.rateLimits?.fiveHour.usedPercentage == 42.0)
    #expect(payload.sessionId == "abc123")
}

@Test func parsesSessionFile() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-session", withExtension: "jsonl")!
    let messages = try UsageParser.parseSessionFile(at: url)

    #expect(messages.count == 4)
    let assistants = messages.filter { $0.type == "assistant" }
    #expect(assistants.count == 2)
}

@Test func aggregatesDailyUsageFromStatsCache() throws {
    let url = Bundle.module.url(forResource: "Fixtures/sample-stats-cache", withExtension: "json")!
    let cache = try UsageParser.parseStatsCache(at: url)
    let daily = UsageParser.dailyUsageFromStatsCache(cache, date: "2026-04-05")

    #expect(daily.date == "2026-04-05")
    #expect(daily.sessionCount == 8)
    #expect(daily.messageCount == 120)
    #expect(daily.modelsUsed.contains("claude-opus-4-6"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageParser`
Expected: FAIL — `UsageParser` not found.

- [ ] **Step 3: Create UsageParser**

Create `Sources/CCMaxOKCore/Services/UsageParser.swift`:

```swift
import Foundation

public enum UsageParser {

    public static func parseStatsCache(at url: URL) throws -> StatsCache {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StatsCache.self, from: data)
    }

    public static func parseStatuslinePayload(at url: URL) throws -> StatuslinePayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StatuslinePayload.self, from: data)
    }

    public static func parseSessionFile(at url: URL) throws -> [SessionMessage] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return SessionMessage.parseJSONL(content)
    }

    public static func dailyUsageFromStatsCache(_ cache: StatsCache, date: String) -> DailyUsage {
        let activity = cache.dailyActivity[date]
        let modelTokens = cache.dailyModelTokens[date] ?? [:]
        let totalTokens = modelTokens.values.reduce(0, +)

        return DailyUsage(
            date: date,
            sessionCount: activity?.sessionCount ?? 0,
            messageCount: activity?.messageCount ?? 0,
            totalInputTokens: totalTokens,
            totalOutputTokens: 0,
            totalCacheReadTokens: 0,
            totalCacheCreationTokens: 0,
            modelsUsed: Array(modelTokens.keys)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageParser`
Expected: PASS — all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Services/UsageParser.swift Tests/CCMaxOKCoreTests/Services/UsageParserTests.swift
git commit -m "feat: add UsageParser for stats-cache, statusline, and JSONL parsing"
```

---

### Task 9: StatuslineSetup — Script Deployment & Settings Patch

**Files:**
- Create: `Sources/CCMaxOKCore/Services/StatuslineSetup.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/StatuslineSetupTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/StatuslineSetupTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func deploysStatuslineScript() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    try StatuslineSetup.deployScript(fileAccess: fam)

    let scriptPath = fam.statuslineScriptPath
    #expect(FileManager.default.fileExists(atPath: scriptPath.path()))

    let content = try String(contentsOf: scriptPath, encoding: .utf8)
    #expect(content.contains("live-status.json"))

    // Verify executable permission
    let attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path())
    let perms = (attrs[.posixPermissions] as? Int) ?? 0
    #expect(perms & 0o111 != 0) // has execute bit
}

@Test func patchesSettingsJson() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)

    // Create existing settings.json
    let existingSettings = """
    {
      "enabledPlugins": {
        "superpowers@claude-plugins-official": true
      }
    }
    """
    try existingSettings.write(to: fam.settingsPath, atomically: true, encoding: .utf8)

    try StatuslineSetup.patchSettings(fileAccess: fam)

    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    // Existing settings preserved
    #expect(json["enabledPlugins"] != nil)

    // Statusline added
    let statusLine = json["statusLine"] as? [String: Any]
    #expect(statusLine?["type"] as? String == "command")
    let command = statusLine?["command"] as? String
    #expect(command?.contains("statusline.sh") == true)
}

@Test func patchesSettingsWhenNoFileExists() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)

    try StatuslineSetup.patchSettings(fileAccess: fam)

    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let statusLine = json["statusLine"] as? [String: Any]
    #expect(statusLine?["type"] as? String == "command")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatuslineSetup`
Expected: FAIL — `StatuslineSetup` not found.

- [ ] **Step 3: Create StatuslineSetup**

Create `Sources/CCMaxOKCore/Services/StatuslineSetup.swift`:

```swift
import Foundation

public enum StatuslineSetup {

    public static func deployScript(fileAccess: FileAccessManager) throws {
        let scriptContent = """
        #!/bin/bash
        cat /dev/stdin > \(fileAccess.liveStatusPath.path())
        """

        try fileAccess.ensureCCMaxOKDirectory()
        let scriptPath = fileAccess.statuslineScriptPath
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.path()
        )
    }

    public static func patchSettings(fileAccess: FileAccessManager) throws {
        var settings: [String: Any] = [:]

        let settingsPath = fileAccess.settingsPath
        if FileManager.default.fileExists(atPath: settingsPath.path()) {
            let data = try Data(contentsOf: settingsPath)
            if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
        }

        settings["statusLine"] = [
            "type": "command",
            "command": fileAccess.statuslineScriptPath.path()
        ] as [String: String]

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsPath, options: .atomic)
    }

    public static func isSetupComplete(fileAccess: FileAccessManager) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileAccess.statuslineScriptPath.path()) else { return false }
        guard fm.fileExists(atPath: fileAccess.settingsPath.path()) else { return false }

        guard let data = try? Data(contentsOf: fileAccess.settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }
        return command.contains("statusline.sh")
    }

    public static func setup(fileAccess: FileAccessManager) throws {
        try deployScript(fileAccess: fileAccess)
        try patchSettings(fileAccess: fileAccess)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StatuslineSetup`
Expected: PASS — all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Services/StatuslineSetup.swift Tests/CCMaxOKCoreTests/Services/StatuslineSetupTests.swift
git commit -m "feat: add StatuslineSetup for script deployment and settings patching"
```

---

### Task 10: FileWatcher — FSEvents + Timer Hybrid

**Files:**
- Create: `Sources/CCMaxOKCore/Services/FileWatcher.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/FileWatcherTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/FileWatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func fileWatcherDetectsChange() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let filePath = tempDir.appendingPathComponent("test.json")
    try "initial".write(to: filePath, atomically: true, encoding: .utf8)

    let expectation = Mutex(false)

    let watcher = FileWatcher(watchPaths: [tempDir.path()]) {
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileWatcher`
Expected: FAIL — `FileWatcher` not found.

- [ ] **Step 3: Create FileWatcher**

Create `Sources/CCMaxOKCore/Services/FileWatcher.swift`:

```swift
import Foundation

public final class FileWatcher: @unchecked Sendable {
    private let watchPaths: [String]
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var timer: Timer?
    private let pollingInterval: TimeInterval

    public init(
        watchPaths: [String],
        pollingInterval: TimeInterval = 300, // 5 minutes
        onChange: @escaping @Sendable () -> Void
    ) {
        self.watchPaths = watchPaths
        self.pollingInterval = pollingInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        startFSEvents()
    }

    public func startPolling() {
        stopFSEvents()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(
                withTimeInterval: self.pollingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.onChange()
            }
        }
    }

    public func stop() {
        stopFSEvents()
        timer?.invalidate()
        timer = nil
    }

    private func startFSEvents() {
        let pathsToWatch = watchPaths as CFArray
        var context = FSEventStreamContext()
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
        context.info = unsafeSelf

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    private func stopFSEvents() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileWatcher`
Expected: PASS — 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Services/FileWatcher.swift Tests/CCMaxOKCoreTests/Services/FileWatcherTests.swift
git commit -m "feat: add FileWatcher with FSEvents and polling modes"
```

---

### Task 11: UsageAnalyzer — Trends, Recommendations, Plan Comparison

**Files:**
- Create: `Sources/CCMaxOKCore/Services/UsageAnalyzer.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/UsageAnalyzerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/UsageAnalyzerTests.swift`:

```swift
import Foundation
import Testing
@testable import CCMaxOKCore

@Test func detectsOveruseAlert5h80() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 82.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 30.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 3)
    )
    let alerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "overuse_5h_80" })
}

@Test func detectsOveruseAlert5h95() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 96.0, resetsAt: Date().timeIntervalSince1970 + 1800),
        sevenDay: RateLimitWindow(usedPercentage: 50.0, resetsAt: Date().timeIntervalSince1970 + 86400)
    )
    let alerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "overuse_5h_95" })
}

@Test func detectsOveruseAlert7d70() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 20.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 75.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 2)
    )
    let alerts = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "overuse_7d_70" })
}

@Test func detectsWasteAlert5h() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 30.0, resetsAt: Date().timeIntervalSince1970 + 2400),
        sevenDay: RateLimitWindow(usedPercentage: 40.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 3)
    )
    let alerts = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "waste_5h" })
}

@Test func detectsWasteAlert7d() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 50.0, resetsAt: Date().timeIntervalSince1970 + 3600),
        sevenDay: RateLimitWindow(usedPercentage: 40.0, resetsAt: Date().timeIntervalSince1970 + 72000)
    )
    let alerts = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)

    #expect(alerts.contains { $0.type == "waste_7d" })
}

@Test func noAlertsWhenNormal() {
    let limits = RateLimits(
        fiveHour: RateLimitWindow(usedPercentage: 50.0, resetsAt: Date().timeIntervalSince1970 + 7200),
        sevenDay: RateLimitWindow(usedPercentage: 40.0, resetsAt: Date().timeIntervalSince1970 + 86400 * 4)
    )
    let overuse = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)
    let waste = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)

    #expect(overuse.isEmpty)
    #expect(waste.isEmpty)
}

@Test func generatesPatternRecommendation() {
    let cache = StatsCache(
        lastComputedDate: "2026-04-06",
        totalSessions: 100,
        totalMessages: 3000,
        dailyActivity: [:],
        dailyModelTokens: [
            "2026-04-05": ["claude-opus-4-6": 300000],
            "2026-04-06": ["claude-opus-4-6": 200000]
        ],
        modelUsage: nil,
        hourCounts: ["14": 200, "15": 300, "16": 250, "10": 20]
    )
    let recs = UsageAnalyzer.patternRecommendations(from: cache)

    // Should detect single-model usage and peak hours
    #expect(!recs.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageAnalyzer`
Expected: FAIL — `UsageAnalyzer` not found.

- [ ] **Step 3: Create UsageAnalyzer**

Create `Sources/CCMaxOKCore/Services/UsageAnalyzer.swift`:

```swift
import Foundation

public struct UsageAlert: Sendable {
    public let type: String
    public let message: String
}

public enum UsageAnalyzer {

    // MARK: - Overuse Alerts

    public static func checkOveruseAlerts(rateLimits: RateLimits) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        let fh = rateLimits.fiveHour
        let sd = rateLimits.sevenDay
        let fhHoursLeft = fh.timeUntilReset / 3600

        if fh.usedPercentage >= 95 {
            let mins = Int(fh.timeUntilReset / 60)
            alerts.append(UsageAlert(
                type: "overuse_5h_95",
                message: "곧 rate limit에 걸립니다! 리셋까지 \(mins)분. 중요한 작업을 먼저 마무리하세요."
            ))
        } else if fh.usedPercentage >= 80 {
            let hours = String(format: "%.1f", fhHoursLeft)
            alerts.append(UsageAlert(
                type: "overuse_5h_80",
                message: "5시간 한도의 \(Int(fh.usedPercentage))%를 사용했어요. 리셋까지 \(hours)시간 남았습니다."
            ))
        }

        if sd.usedPercentage >= 70 {
            let daysLeft = Int(sd.timeUntilReset / 86400)
            alerts.append(UsageAlert(
                type: "overuse_7d_70",
                message: "7일 한도의 \(Int(sd.usedPercentage))% 소진. 리셋까지 \(daysLeft)일 남았어요. 페이스 조절 필요."
            ))
        }

        return alerts
    }

    // MARK: - Waste Alerts

    public static func checkWasteAlerts(rateLimits: RateLimits) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        let fh = rateLimits.fiveHour
        let sd = rateLimits.sevenDay

        // 5h reset within 1 hour AND <40% used
        if fh.timeUntilReset < 3600 && fh.usedPercentage < 40 {
            let mins = Int(fh.timeUntilReset / 60)
            alerts.append(UsageAlert(
                type: "waste_5h",
                message: "\(mins)분 뒤 리셋인데 아직 \(Int(fh.remainingPercentage))%나 남았어요! 지금 쓰면 공짜예요."
            ))
        }

        // 7d reset within 1 day AND <50% used
        if sd.timeUntilReset < 86400 && sd.usedPercentage < 50 {
            let hours = Int(sd.timeUntilReset / 3600)
            alerts.append(UsageAlert(
                type: "waste_7d",
                message: "7일 한도 리셋까지 \(hours)시간인데 \(Int(sd.usedPercentage))%밖에 안 썼어요."
            ))
        }

        return alerts
    }

    // MARK: - Pattern Recommendations

    public static func patternRecommendations(from cache: StatsCache) -> [String] {
        var recommendations: [String] = []

        // Check model diversity
        let allModels = Set(cache.dailyModelTokens.values.flatMap { $0.keys })
        if allModels.count <= 1 {
            recommendations.append("간단한 작업은 Haiku로 처리하면 Opus 한도에 여유가 생겨요.")
        }

        // Check peak hours
        let peak = cache.peakHours(top: 3)
        if peak.count >= 3 {
            let totalTop3 = peak.reduce(0) { $0 + $1.count }
            let totalAll = cache.hourCounts?.values.reduce(0, +) ?? 1
            if totalAll > 0 && Double(totalTop3) / Double(totalAll) > 0.6 {
                let hours = peak.map { "\($0.hour)시" }.joined(separator: ", ")
                recommendations.append("\(hours)에 몰아서 사용하시네요. 분산하면 rate limit 여유가 생겨요.")
            }
        }

        return recommendations
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageAnalyzer`
Expected: PASS — all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Services/UsageAnalyzer.swift Tests/CCMaxOKCoreTests/Services/UsageAnalyzerTests.swift
git commit -m "feat: add UsageAnalyzer with overuse/waste alerts and pattern recommendations"
```

---

### Task 12: NotificationManager

**Files:**
- Create: `Sources/CCMaxOKCore/Services/NotificationManager.swift`
- Create: `Tests/CCMaxOKCoreTests/Services/NotificationManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CCMaxOKCoreTests/Services/NotificationManagerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationManager`
Expected: FAIL — `NotificationManager` not found.

- [ ] **Step 3: Create NotificationManager**

Create `Sources/CCMaxOKCore/Services/NotificationManager.swift`:

```swift
import Foundation
import UserNotifications

public final class NotificationManager: Sendable {
    private let database: DatabaseManager
    private let cooldownSeconds: Double

    public init(database: DatabaseManager, cooldownSeconds: Double = 3600) {
        self.database = database
        self.cooldownSeconds = cooldownSeconds
    }

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func shouldSend(alert: UsageAlert) throws -> Bool {
        try database.canSendNotification(type: alert.type, cooldownSeconds: cooldownSeconds)
    }

    public func recordSent(alert: UsageAlert) throws {
        try database.logNotification(type: alert.type, message: alert.message)
    }

    public func send(alert: UsageAlert) throws {
        guard try shouldSend(alert: alert) else { return }

        let content = UNMutableNotificationContent()
        content.title = "CCMaxOK"
        content.body = alert.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(alert.type)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        try recordSent(alert: alert)
    }

    public func processAlerts(_ alerts: [UsageAlert]) throws {
        for alert in alerts {
            try send(alert: alert)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotificationManager`
Expected: PASS — 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCMaxOKCore/Services/NotificationManager.swift Tests/CCMaxOKCoreTests/Services/NotificationManagerTests.swift
git commit -m "feat: add NotificationManager with cooldown and macOS notification support"
```

---

### Task 13: Xcode App — Project Setup & MenuBarExtra Shell

**Files:**
- Create: `CCMaxOKApp/CCMaxOKApp.swift`
- Create: `CCMaxOKApp/AppState.swift`

Note: This task creates the Xcode project files. The Xcode project (.xcodeproj) must be created manually or with `xcodegen`. For now, these files are authored and the Xcode project is created by opening the Package.swift and adding an app target.

- [ ] **Step 1: Create AppState**

Create `CCMaxOKApp/AppState.swift`:

```swift
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

    var todaySessionCount: Int = 0
    var todayMessageCount: Int = 0
    var todayTotalTokens: Int = 0

    var recommendation: Recommendation?
    var planInsight: PlanInsight?
    var patternTips: [String] = []

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

        // Ensure directory exists
        try? fa.ensureCCMaxOKDirectory()

        // Setup database
        if let db = try? DatabaseManager(path: fa.databasePath.path()) {
            self.database = db
            self.notificationManager = NotificationManager(database: db)
            notificationManager?.requestPermission()
        }

        // Check and run initial setup if needed
        if !StatuslineSetup.isSetupComplete(fileAccess: fa) {
            try? StatuslineSetup.setup(fileAccess: fa)
        }
        isSetupComplete = StatuslineSetup.isSetupComplete(fileAccess: fa)

        // Start file watcher
        let watcher = FileWatcher(watchPaths: [fa.ccmaxokDirectory.path()]) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.fileWatcher = watcher
        watcher.start()

        // Initial load
        refresh()
        loadHistory()
    }

    func refresh() {
        guard let fileAccess else { return }

        // Parse live status
        if let payload = try? UsageParser.parseStatuslinePayload(at: fileAccess.liveStatusPath) {
            if let limits = payload.rateLimits {
                fiveHourUsedPct = limits.fiveHour.usedPercentage
                fiveHourResetsAt = limits.fiveHour.resetDate
                sevenDayUsedPct = limits.sevenDay.usedPercentage
                sevenDayResetsAt = limits.sevenDay.resetDate

                // Store snapshot
                try? database?.insertRateLimitSnapshot(
                    timestamp: Date().timeIntervalSince1970,
                    fiveHourUsedPct: limits.fiveHour.usedPercentage,
                    fiveHourResetsAt: limits.fiveHour.resetsAt,
                    sevenDayUsedPct: limits.sevenDay.usedPercentage,
                    sevenDayResetsAt: limits.sevenDay.resetsAt,
                    model: payload.model.id
                )

                // Check alerts
                let overuse = UsageAnalyzer.checkOveruseAlerts(rateLimits: limits)
                let waste = UsageAnalyzer.checkWasteAlerts(rateLimits: limits)
                try? notificationManager?.processAlerts(overuse + waste)

                // Update recommendation
                recommendation = Recommendation.forRemainingCapacity(
                    remainingPercentage: limits.fiveHour.remainingPercentage,
                    hoursUntilReset: limits.fiveHour.timeUntilReset / 3600
                )
            }
        }

        // Parse today's stats from stats-cache
        if let cache = try? UsageParser.parseStatsCache(at: fileAccess.statsCachePath) {
            let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
            let todayFormatted = String(today.prefix(10))
            let daily = UsageParser.dailyUsageFromStatsCache(cache, date: todayFormatted)
            todaySessionCount = daily.sessionCount
            todayMessageCount = daily.messageCount
            todayTotalTokens = daily.totalTokens

            patternTips = UsageAnalyzer.patternRecommendations(from: cache)
        }
    }

    func loadHistory() {
        guard let database, let fileAccess else { return }

        // Load last 30 days of stats-cache and compute plan insight
        if let cache = try? UsageParser.parseStatsCache(at: fileAccess.statsCachePath) {
            let calendar = Calendar.current
            let today = Date()
            var proExceedDays = 0
            var totalUsagePct = 0.0
            var dayCount = 0

            for dayOffset in 0..<30 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                let dateStr = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withFullDate])
                let formatted = String(dateStr.prefix(10))
                let daily = UsageParser.dailyUsageFromStatsCache(cache, date: formatted)
                if daily.messageCount > 0 {
                    dayCount += 1
                    // Rough Pro limit estimate: if tokens > threshold, counts as exceed
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
        let watcher = FileWatcher(watchPaths: [fileAccess.ccmaxokDirectory.path()]) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.fileWatcher = watcher
        watcher.start()
    }
}
```

- [ ] **Step 2: Create CCMaxOKApp main entry point**

Create `CCMaxOKApp/CCMaxOKApp.swift`:

```swift
import SwiftUI
import CCMaxOKCore

@main
struct CCMaxOKApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appState)
                .frame(width: 320)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(iconColor)
                    .font(.system(size: 8))
                Text("\(Int(appState.fiveHourUsedPct))%")
                    .font(.system(size: 11, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appState.switchToFSEvents()
            case .background:
                appState.switchToPolling()
            default:
                break
            }
        }
        .onAppear {
            appState.setup()
        }
    }

    private var iconColor: Color {
        switch appState.fiveHourAlertLevel {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
```

- [ ] **Step 3: Verify files compile (manual)**

Since this is a SwiftUI app target that requires Xcode, verify by opening in Xcode:

Run: `open /Users/yujuyeon/Dev/jp/mcp_projects/ccmaxok/Package.swift`

Note: The app target needs to be created in Xcode as a macOS App target that depends on CCMaxOKCore. The files in `CCMaxOKApp/` will be added to that target.

- [ ] **Step 4: Commit**

```bash
git add CCMaxOKApp/
git commit -m "feat: add SwiftUI app shell with MenuBarExtra and AppState"
```

---

### Task 14: SwiftUI Views — Popover Cards

**Files:**
- Create: `CCMaxOKApp/Views/MenuBarView.swift`
- Create: `CCMaxOKApp/Views/RateLimitCard.swift`
- Create: `CCMaxOKApp/Views/TodayStatsCard.swift`
- Create: `CCMaxOKApp/Views/RecommendationCard.swift`
- Create: `CCMaxOKApp/Views/PlanInsightCard.swift`

- [ ] **Step 1: Create MenuBarView**

Create `CCMaxOKApp/Views/MenuBarView.swift`:

```swift
import SwiftUI
import CCMaxOKCore

struct MenuBarView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text("CCMaxOK")
                    .font(.headline)
                Text("Claude Code Usage Monitor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    RateLimitCard(
                        fiveHourPct: state.fiveHourUsedPct,
                        fiveHourResetsAt: state.fiveHourResetsAt,
                        sevenDayPct: state.sevenDayUsedPct,
                        sevenDayResetsAt: state.sevenDayResetsAt
                    )

                    TodayStatsCard(
                        sessions: state.todaySessionCount,
                        messages: state.todayMessageCount,
                        tokens: state.todayTotalTokens
                    )

                    if let rec = state.recommendation {
                        RecommendationCard(recommendation: rec, tips: state.patternTips)
                    }

                    if let insight = state.planInsight {
                        PlanInsightCard(insight: insight)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Button("Settings...") {
                    // TODO: Open settings window
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 2: Create RateLimitCard**

Create `CCMaxOKApp/Views/RateLimitCard.swift`:

```swift
import SwiftUI

struct RateLimitCard: View {
    let fiveHourPct: Double
    let fiveHourResetsAt: Date
    let sevenDayPct: Double
    let sevenDayResetsAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rate Limits", systemImage: "gauge.medium")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            rateLimitRow(
                label: "5시간 한도",
                percentage: fiveHourPct,
                resetsAt: fiveHourResetsAt
            )

            rateLimitRow(
                label: "7일 한도",
                percentage: sevenDayPct,
                resetsAt: sevenDayResetsAt
            )
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func rateLimitRow(label: String, percentage: Double, resetsAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(colorForPercentage(percentage))
            }

            ProgressView(value: min(percentage, 100), total: 100)
                .tint(colorForPercentage(percentage))

            Text("리셋: \(timeUntil(resetsAt))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func colorForPercentage(_ pct: Double) -> Color {
        if pct >= 80 { return .red }
        if pct >= 60 { return .yellow }
        return .green
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "리셋 완료" }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)일 \(remainingHours)시간 후"
        }
        return "\(hours)시간 \(minutes)분 후"
    }
}
```

- [ ] **Step 3: Create TodayStatsCard**

Create `CCMaxOKApp/Views/TodayStatsCard.swift`:

```swift
import SwiftUI

struct TodayStatsCard: View {
    let sessions: Int
    let messages: Int
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("오늘", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                statItem(value: "\(sessions)", label: "세션")
                Spacer()
                statItem(value: "\(messages)", label: "메시지")
                Spacer()
                statItem(value: formatTokens(tokens), label: "토큰")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
```

- [ ] **Step 4: Create RecommendationCard**

Create `CCMaxOKApp/Views/RecommendationCard.swift`:

```swift
import SwiftUI
import CCMaxOKCore

struct RecommendationCard: View {
    let recommendation: Recommendation
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("추천", systemImage: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .textCase(.uppercase)

            Text(recommendation.message)
                .font(.caption)

            ForEach(recommendation.suggestions, id: \.self) { suggestion in
                Label(suggestion, systemImage: "arrow.right.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !tips.isEmpty {
                Divider()
                ForEach(tips, id: \.self) { tip in
                    Label(tip, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 5: Create PlanInsightCard**

Create `CCMaxOKApp/Views/PlanInsightCard.swift`:

```swift
import SwiftUI
import CCMaxOKCore

struct PlanInsightCard: View {
    let insight: PlanInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("플랜 인사이트", systemImage: "chart.bar.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(insight.summary)
                .font(.caption)

            HStack {
                Label("Pro 한도 초과일", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(insight.proExceedDays)일 / \(insight.totalDays)일")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(insight.proExceedDays > 5 ? .red : .green)
            }

            HStack {
                Text(insight.recommendation == .keepMax ? "Max 유지 추천" : "Pro 전환 추천")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(insight.recommendation == .keepMax ? .orange : .green)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add CCMaxOKApp/Views/
git commit -m "feat: add SwiftUI popover views — rate limits, stats, recommendations, plan insight"
```

---

### Task 15: Settings View & Entitlements

**Files:**
- Create: `CCMaxOKApp/Views/SettingsView.swift`
- Create: `CCMaxOKApp/CCMaxOKApp.entitlements`
- Create: `CCMaxOKApp/Resources/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Create SettingsView**

Create `CCMaxOKApp/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("alert_overuse_5h_80") private var overuse5h80 = true
    @AppStorage("alert_overuse_5h_95") private var overuse5h95 = true
    @AppStorage("alert_overuse_7d_70") private var overuse7d70 = true
    @AppStorage("alert_waste_5h") private var waste5h = true
    @AppStorage("alert_waste_7d") private var waste7d = true
    @AppStorage("alert_weekly_report") private var weeklyReport = true

    @AppStorage("threshold_overuse_5h_1") private var threshold5h1 = 80.0
    @AppStorage("threshold_overuse_5h_2") private var threshold5h2 = 95.0
    @AppStorage("threshold_overuse_7d") private var threshold7d = 70.0

    var body: some View {
        Form {
            Section("과다 사용 경고") {
                Toggle("5시간 한도 \(Int(threshold5h1))% 도달", isOn: $overuse5h80)
                Toggle("5시간 한도 \(Int(threshold5h2))% 도달", isOn: $overuse5h95)
                Toggle("7일 한도 \(Int(threshold7d))% 도달", isOn: $overuse7d70)
            }

            Section("낭비 방지 알림") {
                Toggle("5시간 리셋 임박 + 여유 많음", isOn: $waste5h)
                Toggle("7일 리셋 임박 + 사용률 저조", isOn: $waste7d)
                Toggle("주간 리포트 (매주 월요일)", isOn: $weeklyReport)
            }

            Section("임계값 설정") {
                HStack {
                    Text("5시간 경고 1단계")
                    Slider(value: $threshold5h1, in: 50...95, step: 5)
                    Text("\(Int(threshold5h1))%")
                        .frame(width: 40)
                }
                HStack {
                    Text("5시간 경고 2단계")
                    Slider(value: $threshold5h2, in: 80...100, step: 5)
                    Text("\(Int(threshold5h2))%")
                        .frame(width: 40)
                }
                HStack {
                    Text("7일 경고")
                    Slider(value: $threshold7d, in: 50...90, step: 5)
                    Text("\(Int(threshold7d))%")
                        .frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
    }
}
```

- [ ] **Step 2: Create entitlements file**

Create `CCMaxOKApp/CCMaxOKApp.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Create PrivacyInfo.xcprivacy**

Create `CCMaxOKApp/Resources/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyTracking</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 4: Commit**

```bash
git add CCMaxOKApp/Views/SettingsView.swift CCMaxOKApp/CCMaxOKApp.entitlements CCMaxOKApp/Resources/PrivacyInfo.xcprivacy
git commit -m "feat: add SettingsView with notification toggles, entitlements, and privacy manifest"
```

---

### Task 16: Xcode Project Creation & Integration

**Files:**
- Create Xcode project that references the Swift Package and app files

- [ ] **Step 1: Create Xcode project**

Open Xcode and create a new macOS App project:
- Product Name: `CCMaxOK`
- Team: (your team)
- Organization Identifier: `com.ccmaxok`
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: macOS 15.0

Save it in the project root directory.

- [ ] **Step 2: Add local package dependency**

In Xcode:
1. File → Add Package Dependencies
2. Click "Add Local..."
3. Select the project root (where Package.swift is)
4. Add `CCMaxOKCore` library to the app target

- [ ] **Step 3: Add source files to app target**

Drag the `CCMaxOKApp/` directory contents into the Xcode project navigator under the app target. Ensure all `.swift` files are added to the app target's Compile Sources.

- [ ] **Step 4: Configure entitlements**

In the app target's Signing & Capabilities:
1. Add "App Sandbox" capability
2. Point to `CCMaxOKApp/CCMaxOKApp.entitlements`

- [ ] **Step 5: Build and run**

Run: Cmd+R in Xcode
Expected: App appears in menu bar with `● 0%` label. Clicking shows the popover with empty cards.

- [ ] **Step 6: Commit**

```bash
git add CCMaxOK.xcodeproj/ CCMaxOKApp/
git commit -m "feat: create Xcode project with CCMaxOKCore package integration"
```

---

### Task 17: End-to-End Test — Manual Verification

- [ ] **Step 1: Run all unit tests**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 2: Build the app**

Run: `xcodebuild -project CCMaxOK.xcodeproj -scheme CCMaxOK -configuration Debug build`
Expected: Build succeeds.

- [ ] **Step 3: Test statusline integration manually**

Create a test live-status.json to verify the app picks up changes:

```bash
mkdir -p ~/.claude/ccmaxok
cat > ~/.claude/ccmaxok/live-status.json << 'EOF'
{
  "session_id": "test123",
  "model": {"id": "claude-opus-4-6", "display_name": "Claude Opus 4.6"},
  "cost": {"total_cost_usd": 0, "total_duration_ms": 1000, "total_api_duration_ms": 800, "total_lines_added": 10, "total_lines_removed": 2},
  "context_window": {"total_input_tokens": 5000, "total_output_tokens": 1000, "used_percentage": 3.0, "current_usage": {"input_tokens": 1000, "output_tokens": 200, "cache_read_input_tokens": 500, "cache_creation_input_tokens": 100}, "context_window_size": 200000},
  "rate_limits": {"five_hour": {"used_percentage": 42.0, "resets_at": 9999999999}, "seven_day": {"used_percentage": 28.0, "resets_at": 9999999999}}
}
EOF
```

Expected: Menu bar icon updates to show `● 42%` with yellow color. Popover shows rate limit bars, 42% for 5h and 28% for 7d.

- [ ] **Step 4: Verify notification permission**

Open System Settings → Notifications → CCMaxOK
Expected: Notification permission requested on first launch.

- [ ] **Step 5: Clean up test data**

```bash
rm ~/.claude/ccmaxok/live-status.json
```

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "chore: end-to-end verification complete"
```
