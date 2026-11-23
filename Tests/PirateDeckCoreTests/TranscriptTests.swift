import XCTest
@testable import PirateDeckCore

final class TranscriptTests: XCTestCase {
    func testPlainTextFormat() {
        let t = Transcript()
        t.append(.sent, "i")
        t.append(.received, "\u{1B}[32mBus Pirate 5 REV10\u{1B}[0m\r\nHiZ> ")
        XCTAssertEqual(t.plainText(), ">> i\nBus Pirate 5 REV10\nHiZ> ")
        XCTAssertEqual(t.rawText(), ">> i\nBus Pirate 5 REV10\r\nHiZ> ")
    }
    func testOnChangeFires() {
        let t = Transcript()
        let e = expectation(description: "change")
        t.onChange = { e.fulfill() }
        t.append(.sent, "v")
        wait(for: [e], timeout: 1)
    }
}
