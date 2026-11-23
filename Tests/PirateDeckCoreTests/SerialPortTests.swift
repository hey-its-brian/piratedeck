import XCTest
import Darwin
@testable import PirateDeckCore

final class SerialPortTests: XCTestCase {
    func testOpenFailsForMissingPath() {
        XCTAssertThrowsError(try POSIXSerialPort(path: "/dev/cu.does-not-exist")) {
            guard case TransportError.openFailed = $0 else { return XCTFail("wrong error: \($0)") }
        }
    }
    func testRoundTripAndDisconnectOnPseudoTerminal() async throws {
        var master: Int32 = 0, slave: Int32 = 0
        var name = [CChar](repeating: 0, count: 128)
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        let port = try POSIXSerialPort(path: String(cString: name))
        Darwin.close(slave)
        XCTAssertEqual(Darwin.write(master, "HiZ> ", 5), 5)
        var it = port.incoming.makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first.map { String(decoding: $0, as: UTF8.self) }, "HiZ> ")
        try port.write(Data("i\r".utf8))
        var buf = [UInt8](repeating: 0, count: 8)
        XCTAssertEqual(Darwin.read(master, &buf, 8), 2)
        Darwin.close(master)                      // same as unplug
        let end = await it.next()
        XCTAssertNil(end)
        XCTAssertThrowsError(try port.write(Data("x".utf8)))
    }
}
