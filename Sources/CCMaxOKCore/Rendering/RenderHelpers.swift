import Foundation

public enum RenderHelpers {
    public static func shortTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "now" }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "\(days)d\(remHours)h"
        }
        return "\(hours)h\(String(format: "%02d", minutes))m"
    }
}
