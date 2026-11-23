import XCTest
@testable import PirateDeckCore

final class PortFinderTests: XCTestCase {
    func testFindsTerminalPortAndIgnoresOtherDevices() {
        let names = ["cu.usbmodem1301", "cu.usbmodem5buspirate3", "cu.usbmodem5buspirate1", "tty.usbmodem5buspirate1", "cu.Bluetooth-Incoming-Port"]
        XCTAssertEqual(PortFinder.terminalPort(from: names), .found("/dev/cu.usbmodem5buspirate1"))
    }
    func testNoBusPirate() {
        XCTAssertEqual(PortFinder.terminalPort(from: ["cu.usbmodem1301"]), PortChoice.none)
    }
    func testTwoBusPiratesAreAmbiguous() {
        let names = ["cu.usbmodem5buspirate1", "cu.usbmodem5buspirate3", "cu.usbmodem7buspirate1", "cu.usbmodem7buspirate3"]
        XCTAssertEqual(PortFinder.terminalPort(from: names), .ambiguous(["/dev/cu.usbmodem5buspirate1", "/dev/cu.usbmodem7buspirate1"]))
    }
}
