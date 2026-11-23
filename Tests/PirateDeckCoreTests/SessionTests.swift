import XCTest
@testable import PirateDeckCore

final class SessionTests: XCTestCase {
    func makeSession() -> (BusPirateSession, FakeTransport, Transcript) {
        let f = FakeTransport(); let t = Transcript()
        return (BusPirateSession(transport: f, transcript: t), f, t)
    }
    func testStartAtPrompt() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "\r\nHiZ> "]
        try await s.start()
        let mode = await s.currentMode
        XCTAssertEqual(mode, "HiZ")
    }
    func testStartAnswersVT100QuestionWithN() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "VT100 compatible color mode? (Y/n)> ", "n\r": "n\r\nHiZ> "]
        try await s.start()
        XCTAssertTrue(f.written.contains("n\r"))
    }
    func testStartLeavesMenuWithX() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "x. Exit\r\nMode > ", "x\r": "x\r\nHiZ> "]
        try await s.start()
        XCTAssertTrue(f.written.contains("x\r"))
    }
    func testStartTimesOutOnSilentPort() async {
        let (s, _, _) = makeSession()
        do { try await s.start(timeout: .milliseconds(300)); XCTFail("no error") }
        catch { XCTAssertEqual(error as? SessionError, .timeout(partial: "")) }
    }
    func testSendReturnsReplyWithoutEchoAndPrompt() async throws {
        let (s, f, t) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "i\r": "i\r\n\r\nBus Pirate 5 REV10\r\nActive mode: HiZ\r\n\r\nHiZ> "]
        try await s.start()
        let reply = try await s.send("i")
        XCTAssertEqual(reply, "Bus Pirate 5 REV10\r\nActive mode: HiZ")
        XCTAssertTrue(t.plainText().contains(">> i"))
    }
    func testSendTracksModeChange() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "m i2c\r": "m i2c\r\nMode: I2C\r\nI2C> "]
        try await s.start(); _ = try await s.send("m i2c")
        let mode = await s.currentMode
        XCTAssertEqual(mode, "I2C")
    }
    func testSendTimeoutCarriesPartialText() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "?\r": "?\r\nGeneral commands\r\n--more--"]
        try await s.start()
        do { _ = try await s.send("?", timeout: .milliseconds(300)); XCTFail("no error") }
        catch { XCTAssertEqual(error as? SessionError, .timeout(partial: "General commands\r\n--more--")) }
    }
    func testSendThrowsDisconnectedWhenStreamEnds() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> "]
        try await s.start(); f.disconnect()
        do { _ = try await s.send("i"); XCTFail("no error") }
        catch { XCTAssertEqual(error as? SessionError, .disconnected) }
    }
    func testShutdownSendsHiZOnlyWhenNotInHiZ() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "m i2c\r": "I2C> ", "m hiz\r": "HiZ> "]
        try await s.start(); await s.shutdown()
        XCTAssertFalse(f.written.contains("m hiz\r"))
        let (s2, f2, _) = makeSession()
        f2.autoReplies = f.autoReplies
        try await s2.start(); _ = try await s2.send("m i2c"); await s2.shutdown()
        XCTAssertTrue(f2.written.contains("m hiz\r"))
    }
    func testSendInteractiveReturnsAtMenuPromptWithoutTimeout() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "m\r": "m\r\nMode selection\r\n x. Exit\r\nMode > "]
        try await s.start()
        let reply = try await s.sendInteractive("m", timeout: .seconds(2))
        XCTAssertEqual(reply, "Mode selection\r\n x. Exit\r\nMode >")
        let mode = await s.currentMode
        XCTAssertEqual(mode, "HiZ")
    }
    func testSendInteractiveTimesOutWhenDeviceIsSilent() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> "]
        try await s.start()
        do { _ = try await s.sendInteractive("zzz", timeout: .milliseconds(300)); XCTFail("no error") }
        catch { XCTAssertEqual(error as? SessionError, .timeout(partial: "")) }
    }
    // Real firmware e9cb31e echo: the line is printed again with a completion hint.
    func testRealFirmwareEchoWithHintIsRemoved() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = [
            "\r": "\rHiZ> \r\n\r\nHiZ> \u{03}",
            "i\r": "\rHiZ> iflash\r\rHiZ> i\r\n\r\nBus Pirate 5 REV10\r\nActive mode: HiZ\r\n\r\nHiZ> \u{03}",
            "x\r": "\rHiZ> xflash\r\rHiZ> x\r\n\r\nInvalid command: x. Type ? for help.\r\n\u{07}HiZ> \u{03}",
        ]
        try await s.start()
        XCTAssertFalse(f.written.contains("x\r"), "start must not send x at a mode prompt")
        let reply = try await s.send("i")
        XCTAssertEqual(reply, "Bus Pirate 5 REV10\r\nActive mode: HiZ")
        let bad = try await s.send("x")
        XCTAssertEqual(bad, "Invalid command: x. Type ? for help.")
    }
}
