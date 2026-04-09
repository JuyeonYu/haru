import Foundation

public enum ConnectionState: Equatable {
    /// Claude config directory does not exist at all
    case noClaudeDir
    /// Config dir exists, statusline hook installed, but no data yet
    case waitingFirstRun
    /// live-status.json parsed but rateLimits is nil
    case connectedNoLimits
    /// Full live data available
    case connected
}
