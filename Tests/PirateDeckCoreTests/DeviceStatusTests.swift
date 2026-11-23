import XCTest
@testable import PirateDeckCore

final class DeviceStatusTests: XCTestCase {
    func testCaptureFileIsPresent() {
        XCTAssertTrue(CaptureFixtures.iReplyI2CPowered.contains("Active mode: I2C"))
        XCTAssertTrue(CaptureFixtures.iReplyUARTOff.contains("Active mode: UART"))
    }
    func testParsesPoweredI2CStatus() throws {
        let s = try XCTUnwrap(DeviceStatus.parse(CaptureFixtures.iReplyI2CPowered))
        XCTAssertEqual(s.mode, "I2C")
        XCTAssertEqual(s.settings, [Setting(key: "I2C speed", value: "400 kHz"), Setting(key: "Clock stretching", value: "OFF")])
        XCTAssertEqual(s.pullupsOn, true); XCTAssertEqual(s.powerOn, true)
        XCTAssertEqual(s.setVoltage, 3.3); XCTAssertEqual(s.measuredVoltage, 3.29)
        XCTAssertEqual(s.currentMilliamps, 3.1)
        XCTAssertEqual(s.pins.count, 10)
        XCTAssertEqual(s.pins[0], PinState(number: 1, name: "Vout", label: "003.1mA", voltage: 3.3))
        XCTAssertEqual(s.pins[1], PinState(number: 2, name: "IO0", label: "SDA", voltage: 3.3))
        XCTAssertEqual(s.pins[2].label, "SCL")
        XCTAssertEqual(s.pins[9], PinState(number: 10, name: "GND", label: "GND", voltage: nil))
    }
    func testParsesUARTStatusWithPowerOff() throws {
        let s = try XCTUnwrap(DeviceStatus.parse(CaptureFixtures.iReplyUARTOff))
        XCTAssertEqual(s.mode, "UART"); XCTAssertEqual(s.powerOn, false); XCTAssertEqual(s.pullupsOn, false)
        XCTAssertNil(s.setVoltage); XCTAssertEqual(s.settings.count, 6)
        XCTAssertEqual(s.pins[5].label, "TX->"); XCTAssertEqual(s.pins[6].label, "RX<-")
        XCTAssertEqual(s.pins[0].label, "OFF"); XCTAssertEqual(s.pins[0].voltage, 0.0)
    }
    func testHiZStatusHasNoSettings() throws {
        let s = try XCTUnwrap(DeviceStatus.parse(Fixtures.infoReply))
        XCTAssertEqual(s.mode, "HiZ"); XCTAssertTrue(s.settings.isEmpty); XCTAssertTrue(s.pins.isEmpty)
        XCTAssertNil(s.powerOn)
    }
    func testBadPinTableGivesEmptyPinsAndKeepsRawText() {
        let bad = "Active mode: I2C\r\n\r\n1.Vout\t2.IO0\r\nOFF\tSDA\tSCL\r\n"
        let s = DeviceStatus.parse(bad)
        XCTAssertEqual(s?.pins, []); XCTAssertTrue(s?.rawPinTable.contains("1.Vout") ?? false)
    }
    func testParsesVReply() {
        XCTAssertEqual(DeviceStatus.parsePinTable(CaptureFixtures.vReplyI2COff).pins[1].voltage, 0.0)
        XCTAssertEqual(DeviceStatus.parsePinTable(CaptureFixtures.vReplyI2CPowered).pins[1].voltage, 3.3)
    }
    func testNotAStatusReply() { XCTAssertNil(DeviceStatus.parse("Invalid command: x.")) }
}
