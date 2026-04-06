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
