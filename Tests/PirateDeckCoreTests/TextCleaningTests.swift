import XCTest
@testable import PirateDeckCore

final class TextCleaningTests: XCTestCase {
    func testStripsColorCodes() {
        XCTAssertEqual(stripANSI("\u{1B}[0;32mHiZ>\u{1B}[0m "), "HiZ> ")
    }
    func testStripsCursorAndScrollRegionCodes() {
        XCTAssertEqual(stripANSI("\u{1B}[1;24r\u{1B}[24;1H\u{1B}[?25lI2C>\u{1B}7\u{1B}8"), "I2C>")
    }
    func testModePromptFound() {
        XCTAssertEqual(modePrompt(in: "some reply\r\nHiZ> "), "HiZ")
        XCTAssertEqual(modePrompt(in: "\u{1B}[32m1WIRE>\u{1B}[0m"), "1WIRE")
    }
    func testMenuPromptIsNotModePrompt() {
        XCTAssertNil(modePrompt(in: "x. Exit\r\nMode > "))
        XCTAssertNil(modePrompt(in: "Bits (1) > "))
        XCTAssertNil(modePrompt(in: "reply in progress"))
    }
    func testVT100Question() {
        XCTAssertTrue(isVT100Question("VT100 compatible color mode? (Y/n)> "))
        XCTAssertFalse(isVT100Question("HiZ> "))
    }
    // Real firmware e9cb31e output: the prompt is followed by ETX (0x03), errors by BEL (0x07).
    func testStripsControlCharactersButKeepsLineEnds() {
        XCTAssertEqual(stripANSI("\u{07}HiZ> \u{03}"), "HiZ> ")
        XCTAssertEqual(stripANSI("a\r\n\tb"), "a\r\n\tb")
    }
    func testModePromptFoundWithTrailingETX() {
        XCTAssertEqual(modePrompt(in: "\rHiZ> \r\n\r\nHiZ> \u{03}"), "HiZ")
    }
}
