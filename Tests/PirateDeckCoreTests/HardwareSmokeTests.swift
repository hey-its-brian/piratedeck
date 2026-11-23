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

    /// Full apply flow on the real device. Runs only with PIRATEDECK_HW_APPLY=1.
    /// It turns the 3.3 V supply ON for a short time: nothing must be connected to the pins.
    func testApplyI2CScanAndReturnToHiZOnRealDevice() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIRATEDECK_HW_APPLY"] == "1", "hardware apply test is off")
        guard case .found(let path) = PortFinder.terminalPort(from: PortFinder.listDevNames()) else {
            return XCTFail("no Bus Pirate port found")
        }
        let transcript = Transcript()
        let session = BusPirateSession(transport: try POSIXSerialPort(path: path), transcript: transcript)
        let controller = DeviceController(session: session)
        var settings = ModeSettings()
        settings.i2cSpeedKHz = 100
        do {
            try await session.start()
            let result = try await controller.apply(ApplyRequest(
                mode: .i2c, settings: settings,
                power: .busPirate(PowerRequest(volts: 3.3, milliamps: 300)), pullups: true))
            print("APPLY-RESULT warnings=\(result.warnings) enabled=\(result.actionsEnabled)")
            XCTAssertTrue(result.actionsEnabled)
            XCTAssertEqual(result.warnings, [])
            XCTAssertEqual(result.status?.mode, "I2C")
            XCTAssertEqual(result.status?.settings.first, Setting(key: "I2C speed", value: "100 kHz"))
            XCTAssertEqual(result.status?.pullupsOn, true)
            XCTAssertEqual(result.status?.pins.dropFirst().first?.label, "SDA")
            let scan = try await controller.run(Actions.i2cScan)
            XCTAssertNotNil(Actions.scanSummary(scan))
        } catch {
            XCTFail("apply failed: \(error)")
        }
        // Always go back to the safe state.
        let hiz = try? await controller.apply(ApplyRequest(mode: .hiz, settings: ModeSettings(), power: .target, pullups: false))
        XCTAssertNotNil(hiz)
        let after = try? await controller.refresh()
        XCTAssertEqual(after?.mode, "HiZ")
        print("TRANSCRIPT-BEGIN\n\(transcript.plainText())\nTRANSCRIPT-END")
        await session.shutdown()
    }

    /// SPI and UART menus on the real device, no power. Runs only with PIRATEDECK_HW_MODES=1.
    func testSPIAndUARTMenusOnRealDevice() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIRATEDECK_HW_MODES"] == "1", "hardware mode test is off")
        guard case .found(let path) = PortFinder.terminalPort(from: PortFinder.listDevNames()) else {
            return XCTFail("no Bus Pirate port found")
        }
        let transcript = Transcript()
        let session = BusPirateSession(transport: try POSIXSerialPort(path: path), transcript: transcript)
        let controller = DeviceController(session: session)
        var settings = ModeSettings()
        settings.spiSpeedKHz = 500; settings.spiClockIdleHigh = true; settings.spiTrailingEdge = true
        settings.uartBaud = 9600; settings.uartParity = .even; settings.uartStopBits = 2
        do {
            try await session.start()
            let spiUnknown = try await ModeConfigurator.enter(.spi, settings: settings, session: session)
            let spi = try await controller.refresh()
            print("SPI unknown=\(spiUnknown) settings=\(spi?.settings ?? [])")
            let uartUnknown = try await ModeConfigurator.enter(.uart, settings: settings, session: session)
            let uart = try await controller.refresh()
            print("UART unknown=\(uartUnknown) settings=\(uart?.settings ?? [])")
        } catch {
            XCTFail("mode test failed: \(error)")
        }
        _ = try? await controller.apply(ApplyRequest(mode: .hiz, settings: ModeSettings(), power: .target, pullups: false))
        print("TRANSCRIPT-BEGIN\n\(transcript.plainText())\nTRANSCRIPT-END")
        await session.shutdown()
    }
}
