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

@Test func parsesCRLFLineEndings() {
    // Windows 스타일 CRLF와 Mac 고전 CR을 모두 처리해야 한다 (A2).
    let crlf = "{\"type\":\"user\"}\r\n{\"type\":\"assistant\",\"model\":\"claude-opus-4-6\"}\r\n"
    let messages = SessionMessage.parseJSONL(crlf)
    #expect(messages.count == 2)
    #expect(messages[0].type == "user")
    #expect(messages[1].type == "assistant")
    #expect(messages[1].model == "claude-opus-4-6")
}

@Test func skipsMalformedLinesWithoutFailingWhole() {
    // 중간에 깨진 JSON이 섞여 있어도 나머지는 파싱되어야 한다 (A2).
    let mixed = """
    {"type":"user"}
    {this is not json
    {"type":"assistant","usage":{"input_tokens":100,"output_tokens":50}}
    not-json-at-all
    {"type":"user"}
    """
    let messages = SessionMessage.parseJSONL(mixed, context: "test-fixture")
    #expect(messages.count == 3)
    #expect(messages.filter { $0.type == "user" }.count == 2)
    #expect(messages.filter { $0.type == "assistant" }.count == 1)
}
