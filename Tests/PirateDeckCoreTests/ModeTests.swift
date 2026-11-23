import XCTest
@testable import PirateDeckCore

final class ModeSettingsTests: XCTestCase {
    func testValidation() {
        var s = ModeSettings()
        for mode in BusMode.allCases { XCTAssertEqual(s.validationErrors(for: mode), []) }
        s.i2cSpeedKHz = 0
        XCTAssertEqual(s.validationErrors(for: .i2c), ["I2C speed must be 1 to 1000 kHz."])
        s.spiDataBits = 9
        XCTAssertEqual(s.validationErrors(for: .spi).count, 1)
    }
    func testMenuAnswersUseSettings() {
        var s = ModeSettings()
        XCTAssertEqual(s.menuAnswers(for: .i2c), ["I2C speed": "400", "Clock stretching": "1"])
        XCTAssertEqual(s.menuAnswers(for: .spi), ["SPI speed": "100", "Data bits": "8", "Clock polarity": "1", "Clock phase": "1", "Chip select": "2"])
        s.spiClockIdleHigh = true; s.uartParity = .odd
        XCTAssertEqual(s.menuAnswers(for: .spi)["Clock polarity"], "2")
        XCTAssertEqual(s.menuAnswers(for: .uart), ["UART speed": "115200", "Data bits": "8", "Parity": "3", "Stop bits": "1"])
        XCTAssertEqual(s.menuAnswers(for: .hiz), [:])
    }
}

final class ModeConfiguratorTests: XCTestCase {
    func makeSession() -> (BusPirateSession, FakeTransport) {
        let f = FakeTransport()
        return (BusPirateSession(transport: f, transcript: Transcript()), f)
    }
    func testEntersI2CAndAnswersMenusByTitle() async throws {
        let (s, f) = makeSession()
        f.autoReplies = ["\r": "HiZ> \u{03}", "m i2c\r": CaptureFixtures.i2cSpeedMenu,
                         "400\r": CaptureFixtures.clockStretchMenu, "1\r": CaptureFixtures.i2cPrompt]
        try await s.start()
        let unknown = try await ModeConfigurator.enter(.i2c, settings: ModeSettings(), session: s)
        XCTAssertEqual(unknown, [])
        XCTAssertEqual(f.written, ["\r", "m i2c\r", "400\r", "1\r"])
        let mode = await s.currentMode
        XCTAssertEqual(mode, "I2C")
    }
    func testAnswersNoToUsePreviousSettings() async throws {
        let (s, f) = makeSession()
        XCTAssertTrue(CaptureFixtures.usePreviousI2C.contains("Use previous settings?"))
        f.autoReplies = ["\r": "HiZ> \u{03}", "m i2c\r": CaptureFixtures.usePreviousI2C,
                         "n\r": CaptureFixtures.i2cSpeedMenu,
                         "400\r": CaptureFixtures.clockStretchMenu, "1\r": CaptureFixtures.i2cPrompt]
        try await s.start()
        _ = try await ModeConfigurator.enter(.i2c, settings: ModeSettings(), session: s)
        XCTAssertEqual(f.written, ["\r", "m i2c\r", "n\r", "400\r", "1\r"])
    }
    func testUnknownMenuTitleGetsReturnNotANumber() async throws {
        let (s, f) = makeSession()
        f.sequences = ["\r": ["HiZ> \u{03}", CaptureFixtures.i2cPrompt]]
        f.autoReplies = ["m i2c\r": "\r\n\r\nMode: I2C\r\nBit banding\r\n 1. no*\r\n 2. yes\r\nx to exit (1) > "]
        try await s.start()
        let unknown = try await ModeConfigurator.enter(.i2c, settings: ModeSettings(), session: s)
        XCTAssertEqual(unknown, ["Bit banding"])
        XCTAssertEqual(f.written, ["\r", "m i2c\r", "\r"])
    }
    func testHiZNeedsNoAnswers() async throws {
        let (s, f) = makeSession()
        f.autoReplies = ["\r": "I2C> \u{03}", "m hiz\r": "\rI2C> m hiz\r\r\n\r\nMode: HiZ\r\nHiZ> \u{03}"]
        try await s.start()
        let unknown = try await ModeConfigurator.enter(.hiz, settings: ModeSettings(), session: s)
        XCTAssertEqual(unknown, [])
        XCTAssertEqual(f.written, ["\r", "m hiz\r"])
    }
    func testAlreadyInModeStillAnswersMenus() async throws {
        let (s, f) = makeSession()
        f.autoReplies = ["\r": "I2C> \u{03}", "m i2c\r": CaptureFixtures.i2cSpeedMenu,
                         "400\r": CaptureFixtures.clockStretchMenu, "1\r": CaptureFixtures.i2cPrompt]
        try await s.start()
        _ = try await ModeConfigurator.enter(.i2c, settings: ModeSettings(), session: s)
        XCTAssertEqual(f.written, ["\r", "m i2c\r", "400\r", "1\r"])
    }
    func testThrowsWhenModeIsNotReached() async throws {
        let (s, f) = makeSession()
        f.sequences = ["\r": ["HiZ> \u{03}"]]
        f.autoReplies = ["m i2c\r": CaptureFixtures.clockStretchMenu, "1\r": CaptureFixtures.clockStretchMenu]
        try await s.start()
        do { _ = try await ModeConfigurator.enter(.i2c, settings: ModeSettings(), session: s); XCTFail("no error") }
        catch { XCTAssertEqual(error as? ConfigError, .modeNotReached(got: "HiZ")) }
    }
}
