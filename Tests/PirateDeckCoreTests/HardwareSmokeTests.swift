import XCTest
@testable import PirateDeckCore

/// Runs only with PIRATEDECK_HW=1 and a Bus Pirate connected.
/// Sends only: Return, `n` or `x` if necessary, and `i`.
final class HardwareSmokeTests: XCTestCase {
    func testConnectAndReadInfoFromRealDevice() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIRATEDECK_HW"] == "1", "hardware test is off")
        guard case .found(let path) = PortFinder.terminalPort(from: PortFinder.listDevNames()) else {
            return XCTFail("no Bus Pirate port found")
        }
        let transcript = Transcript()
        let session = BusPirateSession(transport: try POSIXSerialPort(path: path), transcript: transcript)
        do {
            try await session.start()
            let reply = try await session.send("i")
            let info = try XCTUnwrap(DeviceInfo.parse(reply))
            XCTAssertTrue(info.hardware.hasPrefix("Bus Pirate"))
            XCTAssertFalse(info.modes.isEmpty)
        } catch {
            print("TRANSCRIPT-BEGIN\n\(transcript.plainText())\nTRANSCRIPT-END")
            await session.shutdown()
            throw error
        }
        print("TRANSCRIPT-BEGIN\n\(transcript.plainText())\nTRANSCRIPT-END")
        await session.shutdown()
    }
}
