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

@Test func parsesNestedMessageObject() {
    // 실제 Claude Code jsonl: model/usage/id가 message 객체 안에 중첩.
    let line = """
    {"type":"assistant","sessionId":"s1","requestId":"r1","message":{"id":"msg_abc","model":"claude-opus-4-7","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":200,"cache_creation_input_tokens":10}}}
    """
    let messages = SessionMessage.parseJSONL(line)
    #expect(messages.count == 1)
    #expect(messages[0].model == "claude-opus-4-7")
    #expect(messages[0].messageId == "msg_abc")
    #expect(messages[0].requestId == "r1")
    #expect(messages[0].usage?.inputTokens == 100)
    #expect(messages[0].usage?.cacheCreationInputTokens == 10)
}

@Test func cacheCreationFallsBackToNestedEphemeralFields() {
    // 평탄화 cache_creation_input_tokens가 누락되고 nested cache_creation만 있는 경우.
    let line = """
    {"type":"assistant","message":{"id":"m1","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":2,"cache_creation":{"ephemeral_5m_input_tokens":300,"ephemeral_1h_input_tokens":700}}}}
    """
    let messages = SessionMessage.parseJSONL(line)
    #expect(messages.count == 1)
    #expect(messages[0].usage?.cacheCreationInputTokens == 1000)
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
