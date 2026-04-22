import Foundation

public enum ConnectionState: Equatable {
    /// Claude config directory does not exist at all
    case noClaudeDir
    /// Config dir exists, statusline hook installed, but no data yet
    case waitingFirstRun
    /// live-status.json missing but DB has a past snapshot — show numbers with a freshness label
    case stale(asOf: Date)
    /// No live JSON, no DB snapshot, but token/session counts could be derived from stats-cache / jsonl
    case derived(asOf: Date)
    /// live-status.json parsed but rateLimits is nil
    case connectedNoLimits
    /// Full live data available
    case connected
}
