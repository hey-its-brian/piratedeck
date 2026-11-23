import XCTest
@testable import PirateDeckCore

final class DeviceInfoTests: XCTestCase {
    func testParsesCurrentFirmware() throws {
        let d = try XCTUnwrap(DeviceInfo.parse(Fixtures.infoReply))
        XCTAssertEqual(d.hardware, "Bus Pirate 5 REV10")
        XCTAssertEqual(d.firmware, "main branch @ e9cb31e (Nov 20 2026 08:39:34)")
        XCTAssertEqual(d.commit, "e9cb31e")
        XCTAssertEqual(d.buildDate, "Nov 20 2026 08:39:34")
        XCTAssertEqual(d.modes.count, 14)
        XCTAssertEqual(d.modes.first, "HiZ"); XCTAssertEqual(d.modes.last, "USB")
    }
    func testParsesFactoryFirmwareWithoutCommit() throws {
        let d = try XCTUnwrap(DeviceInfo.parse(Fixtures.oldInfoReply))
        XCTAssertEqual(d.firmware, "v0.1.0 (commit unknown)")
        XCTAssertNil(d.commit); XCTAssertNil(d.buildDate)
        XCTAssertEqual(d.modes, ["HiZ", "1-WIRE", "UART", "I2C", "SPI", "LED"])
    }
    func testRejectsOtherText() {
        XCTAssertNil(DeviceInfo.parse("ets Jul 29 2019 12:21:46\r\nrst:0x1"))
        XCTAssertNil(DeviceInfo.parse(""))
    }
    func testHandlesCRLFAndLeadingBlankLines() {
        XCTAssertNotNil(DeviceInfo.parse("\r\n" + Fixtures.infoReply.replacingOccurrences(of: "\n", with: "\r\n")))
    }
}
