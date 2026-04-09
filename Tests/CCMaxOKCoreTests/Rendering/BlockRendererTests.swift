import Foundation
import Testing
@testable import CCMaxOKCore

@Test func blockRendererTextOutput() {
    let renderer = BlockRenderer()
    let context = RenderContext(
        remainPct: 50,
        sevenDayRemainPct: 60,
        fiveHourResetsAt: .distantFuture,
        sevenDayResetsAt: .distantFuture,
        alertLevel: .warning
    )

    let output = renderer.render(context: context)
    if case .text(let text) = output {
        #expect(text.contains("50%"))
        #expect(text.contains("■"))
        #expect(text.contains("□"))
    } else {
        Issue.record("Expected text output")
    }
}

@Test func blockRendererFullCapacity() {
    let renderer = BlockRenderer()
    let context = RenderContext(
        remainPct: 100,
        sevenDayRemainPct: 100,
        fiveHourResetsAt: .distantFuture,
        sevenDayResetsAt: .distantFuture,
        alertLevel: .normal
    )

    let output = renderer.render(context: context)
    if case .text(let text) = output {
        #expect(text.contains("100%"))
    } else {
        Issue.record("Expected text output")
    }
}

@Test func blockRendererProperties() {
    let renderer = BlockRenderer()
    #expect(renderer.id == "block")
    #expect(renderer.displayName == "Block")
    #expect(!renderer.previewText.isEmpty)
}
