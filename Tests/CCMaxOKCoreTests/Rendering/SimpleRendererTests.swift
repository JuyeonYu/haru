import Foundation
import Testing
@testable import CCMaxOKCore

@Test func simpleRendererTextOutput() {
    let renderer = SimpleRenderer()
    let context = RenderContext(
        remainPct: 85,
        sevenDayRemainPct: 70,
        fiveHourResetsAt: .distantFuture,
        sevenDayResetsAt: .distantFuture,
        alertLevel: .normal
    )

    let output = renderer.render(context: context)
    if case .text(let text) = output {
        #expect(text.contains("85%"))
    } else {
        Issue.record("Expected text output")
    }
}

@Test func simpleRendererZeroPercent() {
    let renderer = SimpleRenderer()
    let context = RenderContext(
        remainPct: 0,
        sevenDayRemainPct: 0,
        fiveHourResetsAt: .distantFuture,
        sevenDayResetsAt: .distantFuture,
        alertLevel: .critical
    )

    let output = renderer.render(context: context)
    if case .text(let text) = output {
        #expect(text.contains("0%"))
    } else {
        Issue.record("Expected text output")
    }
}

@Test func simpleRendererProperties() {
    let renderer = SimpleRenderer()
    #expect(renderer.id == "simple")
    #expect(renderer.displayName == "Simple")
    #expect(!renderer.previewText.isEmpty)
}
