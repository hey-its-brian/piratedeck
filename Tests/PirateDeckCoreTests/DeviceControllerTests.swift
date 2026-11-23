import XCTest
@testable import PirateDeckCore

final class DeviceControllerTests: XCTestCase {
    let i2cPower = PowerRequest(volts: 3.3, milliamps: 300)

    func make(iReply: String = CaptureFixtures.iReplyI2CPowered) -> (DeviceController, FakeTransport, BusPirateSession) {
        let f = FakeTransport()
        f.autoReplies = [
            "\r": "HiZ> \u{03}",
            "w\r": "\r\nPower supply: Disabled\r\n\r\nHiZ> \u{03}",
            "p\r": "\r\nPull-up resistors: Disabled\r\nHiZ> \u{03}",
            "m i2c\r": CaptureFixtures.usePreviousI2C,
            "n\r": CaptureFixtures.i2cSpeedMenu,
            "400\r": CaptureFixtures.clockStretchMenu,
            "1\r": CaptureFixtures.i2cPrompt,
            "W 3.3 300\r": CaptureFixtures.wOnReply + "\u{03}",
            "P\r": CaptureFixtures.pOnReply + "\u{03}",
            "i\r": iReply + "\u{03}",
            "m hiz\r": "\r\nMode: HiZ\r\nHiZ> \u{03}",
        ]
        let s = BusPirateSession(transport: f, transcript: Transcript())
        return (DeviceController(session: s), f, s)
    }

    func testApplyI2CWithPowerSendsCommandsInOrder() async throws {
        let (c, f, s) = make()
        try await s.start()
        let result = try await c.apply(ApplyRequest(mode: .i2c, settings: ModeSettings(), power: .busPirate(i2cPower), pullups: true))
        XCTAssertEqual(f.written, ["\r", "m i2c\r", "n\r", "400\r", "1\r", "W 3.3 300\r", "P\r", "i\r"])
        XCTAssertEqual(result.warnings, [])
        XCTAssertTrue(result.actionsEnabled)
        XCTAssertEqual(result.status?.mode, "I2C")
    }
    func testTargetPowerNeverSendsW() async throws {
        let (c, f, s) = make()
        try await s.start()
        let result = try await c.apply(ApplyRequest(mode: .i2c, settings: ModeSettings(), power: .target, pullups: false))
        XCTAssertFalse(f.written.contains { $0.hasPrefix("W") })
        XCTAssertFalse(f.written.contains("P\r"))
        XCTAssertTrue(result.actionsEnabled)   // the fixture shows 3.3 V on Vout
    }
    func testLowVoltageDisablesActions() async throws {
        let low = CaptureFixtures.iReplyI2CPowered
            .replacingOccurrences(of: "ON (3.3V/3.29V)", with: "ON (3.3V/0.41V)")
        XCTAssertTrue(low.contains("0.41V"))
        let (c, _, s) = make(iReply: low)
        try await s.start()
        let result = try await c.apply(ApplyRequest(mode: .i2c, settings: ModeSettings(), power: .busPirate(i2cPower), pullups: false))
        XCTAssertFalse(result.actionsEnabled)
        XCTAssertEqual(result.warnings, ["VOUT is 0.41 V but the set value is 3.3 V. Check for a short circuit. The actions are disabled."])
    }
    func testTargetPowerWithNoVoltageDisablesActions() async throws {
        let off = "\r\nActive mode: I2C\r\n I2C speed: 400 kHz\r\n\r\nPower supply: OFF\r\n\r\n" + String(CaptureFixtures.vReplyI2COff.drop(while: { $0 != "1" }))
        let (c, _, s) = make(iReply: off)
        try await s.start()
        let result = try await c.apply(ApplyRequest(mode: .i2c, settings: ModeSettings(), power: .target, pullups: false))
        XCTAssertFalse(result.actionsEnabled)
        XCTAssertEqual(result.warnings, ["No voltage on VOUT/VREF. Connect the target supply to the VOUT pin. The actions are disabled."])
    }
    func testPullupWarningWhenNoVoltage() async throws {
        let (c, f, s) = make()
        f.autoReplies["P\r"] = "\r\nPull-up resistors: Enabled (10K ohms @ 0.0V)\r\n\r\nWarning: no/low voltage detected.\r\nEnable power supply (W) or attach external supply to Vout/Vref\r\nI2C> \u{03}"
        try await s.start()
        let result = try await c.apply(ApplyRequest(mode: .i2c, settings: ModeSettings(), power: .target, pullups: true))
        XCTAssertTrue(result.warnings.contains("Pull-ups are on, but no voltage is present."))
    }
    func testHiZStopsAfterModeChange() async throws {
        let (c, f, s) = make()
        try await s.start()
        let result = try await c.apply(ApplyRequest(mode: .hiz, settings: ModeSettings(), power: .busPirate(i2cPower), pullups: true))
        XCTAssertEqual(f.written, ["\r", "m hiz\r"])
        XCTAssertFalse(result.actionsEnabled)
    }
    func testDisconnectDuringApplyThrowsDisconnected() async throws {
        let (c, f, s) = make()
        f.autoReplies["m i2c\r"] = nil
        f.onWrite = { [weak f] text in if text == "m i2c\r" { f?.disconnect() } }
        try await s.start()
        do {
            _ = try await c.apply(ApplyRequest(mode: .i2c, settings: ModeSettings(), power: .target, pullups: false))
            XCTFail("no error")
        } catch { XCTAssertEqual(error as? SessionError, .disconnected) }
    }
    func testRunReturnsCleanReply() async throws {
        let (c, f, s) = make()
        f.autoReplies["scan\r"] = CaptureFixtures.scanEmptyReply + "\u{03}"
        try await s.start()
        let reply = try await c.run(Actions.i2cScan)
        XCTAssertEqual(Actions.scanSummary(reply), "Found 0 addresses, 0 W/R pairs.")
    }
    // Real device: w and p print "Command has no effect in HiZ mode". Send them only in other modes.
    func testSupplyAndPullupsGoOffFirstWhenAModeIsActive() async throws {
        let (c, f, s) = make()
        f.autoReplies["\r"] = "I2C> \u{03}"
        f.autoReplies["w\r"] = "\r\nPower supply: Disabled\r\n\r\nI2C> \u{03}"
        f.autoReplies["p\r"] = "\r\nPull-up resistors: Disabled\r\nI2C> \u{03}"
        try await s.start()
        _ = try await c.apply(ApplyRequest(mode: .hiz, settings: ModeSettings(), power: .target, pullups: false))
        XCTAssertEqual(f.written, ["\r", "w\r", "p\r", "m hiz\r"])
    }
}
