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

    /// Capture of real replies for parser fixtures. Runs only with PIRATEDECK_CAPTURE=1.
    /// It turns the 3.3 V supply ON for a short time: nothing must be connected to the pins.
    func testCapturePowerOnReplies() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIRATEDECK_CAPTURE"] == "1", "capture is off")
        guard case .found(let path) = PortFinder.terminalPort(from: PortFinder.listDevNames()) else {
            return XCTFail("no Bus Pirate port found")
        }
        let transcript = Transcript()
        let session = BusPirateSession(transport: try POSIXSerialPort(path: path), transcript: transcript)
        func enterUntilPrompt() async {
            for _ in 0..<10 {
                _ = try? await session.sendInteractive("", timeout: .seconds(2))
                if modePrompt(in: transcript.plainText()) != nil { return }
            }
        }
        do {
            try await session.start()
            _ = try? await session.sendInteractive("m i2c"); await enterUntilPrompt()
            for line in ["W 3.3", "v", "P", "v", "scan", "i", "w", "p"] {
                _ = try? await session.sendInteractive(line, timeout: .seconds(8))
            }
            _ = try? await session.sendInteractive("m uart"); await enterUntilPrompt()
            _ = try? await session.sendInteractive("i")
        } catch {
            XCTFail("capture failed: \(error)")
        }
        // Always go back to a safe state.
        _ = try? await session.sendInteractive("w")
        _ = try? await session.sendInteractive("p")
        _ = try? await session.sendInteractive("m hiz")
        print("TRANSCRIPT-BEGIN\n\(transcript.plainText())\nTRANSCRIPT-END")
        await session.shutdown()
    }
}
