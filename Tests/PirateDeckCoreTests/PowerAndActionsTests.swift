import XCTest
@testable import PirateDeckCore

final class PowerControlTests: XCTestCase {
    func testCommandFormatAlwaysUppercaseW() {
        XCTAssertEqual(PowerRequest(volts: 3.3, milliamps: 300).command, "W 3.3 300")
        XCTAssertEqual(PowerRequest(volts: 5, milliamps: 0).command, "W 5 0")
        XCTAssertEqual(PowerRequest(volts: 1.8, milliamps: 50).command, "W 1.8 50")
    }
    func testValidation() {
        XCTAssertEqual(PowerRequest(volts: 3.3, milliamps: 300).validationErrors(), [])
        XCTAssertEqual(PowerRequest(volts: 12, milliamps: 300).validationErrors(), ["Voltage must be 0.8 to 5.0 V."])
        XCTAssertEqual(PowerRequest(volts: 3.3, milliamps: 501).validationErrors(), ["Current limit must be 0 to 500 mA."])
    }
    func testSupplyEnabled() {
        XCTAssertTrue(CaptureFixtures.wOnReply.contains("Vreg output"))
        XCTAssertTrue(PowerControl.supplyEnabled(in: CaptureFixtures.wOnReply))
        XCTAssertFalse(PowerControl.supplyEnabled(in: "\r\nPower supply: Disabled\r\n\r\nI2C> "))
    }
    func testVoltageIsGood() {
        XCTAssertTrue(PowerControl.voltageIsGood(set: 3.3, measured: 3.29))
        XCTAssertFalse(PowerControl.voltageIsGood(set: 3.3, measured: 0.4))
        XCTAssertFalse(PowerControl.voltageIsGood(set: 3.3, measured: nil))
    }
}

final class ActionsTests: XCTestCase {
    func testI2CRead() {
        XCTAssertEqual(Actions.i2cRead(address7: 0x50, register: 0, count: 8), "[0xa0 0x00 [0xa1 r:8]")
        XCTAssertEqual(Actions.i2cRead(address7: 0x3c, register: 0x10, count: 0), "[0x78 0x10 [0x79 r:1]")
        XCTAssertEqual(Actions.i2cRead(address7: 0x50, register: 0, count: 999), "[0xa0 0x00 [0xa1 r:255]")
    }
    func testSPITransfer() {
        XCTAssertEqual(Actions.spiTransfer(bytes: [0x9f], readCount: 3), "[0x9f r:3]")
        XCTAssertEqual(Actions.spiTransfer(bytes: [0x03, 0x00], readCount: 0), "[0x03 0x00]")
    }
    func testRawBytes() {
        XCTAssertEqual(Actions.rawBytes(from: "9f 00 0x1A"), [0x9f, 0x00, 0x1a])
        XCTAssertEqual(Actions.rawBytes(from: "9f,00"), [0x9f, 0x00])
        XCTAssertNil(Actions.rawBytes(from: "9f zz"))
        XCTAssertNil(Actions.rawBytes(from: "100"))
        XCTAssertNil(Actions.rawBytes(from: "  "))
    }
    func testScanSummary() {
        XCTAssertEqual(Actions.scanSummary(CaptureFixtures.scanEmptyReply), "Found 0 addresses, 0 W/R pairs.")
        XCTAssertEqual(Actions.scanSummary(CaptureFixtures.scanErrorReply),
                       "Error: No voltage detected on VOUT/VREF pin\nHint: Use W to enable power, or attach an external supply\nError: Pull-up not detected on IO pin\nHint: Use P to enable pull-up resistors, or use external pull-up")
        XCTAssertNil(Actions.scanSummary("nothing"))
    }
}
