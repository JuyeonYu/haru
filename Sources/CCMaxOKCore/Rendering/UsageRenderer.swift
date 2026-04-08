import Foundation
import AppKit

public struct RenderContext: Sendable {
    public let remainPct: Double
    public let sevenDayRemainPct: Double
    public let fiveHourResetsAt: Date
    public let sevenDayResetsAt: Date
    public let alertLevel: AlertLevel

    public init(
        remainPct: Double,
        sevenDayRemainPct: Double,
        fiveHourResetsAt: Date,
        sevenDayResetsAt: Date,
        alertLevel: AlertLevel
    ) {
        self.remainPct = remainPct
        self.sevenDayRemainPct = sevenDayRemainPct
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
        self.alertLevel = alertLevel
    }
}

public enum RenderedOutput: @unchecked Sendable {
    case text(String)
    case symbolAndText(symbol: String, text: String)
    case imageAndText(image: NSImage, text: String)
    case imageOnly(image: NSImage)
}

public protocol UsageRenderer: Sendable {
    var id: String { get }
    var displayName: String { get }
    var previewText: String { get }
    func render(context: RenderContext) -> RenderedOutput
}
