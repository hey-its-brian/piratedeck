import SwiftUI
import AppKit
import PirateDeckCore

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case disconnected(message: String?)
        case searching
        case connected(port: String, info: DeviceInfo?)
        case chooseDevice([String])
    }

    var state: ConnectionState = .disconnected(message: nil)
    var consoleText = ""
    var isBusy = false
    var note: String?

    private let transcript = Transcript()
    private var session: BusPirateSession?
    private var monitor: Task<Void, Never>?

    init() {
        transcript.onChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.consoleText = self.transcript.plainText()
            }
        }
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    func connect(path: String? = nil) async {
        guard !isConnected, state != .searching else { return }
        note = nil
        var portPath = path
        if portPath == nil {
            switch PortFinder.terminalPort(from: PortFinder.listDevNames()) {
            case .found(let found): portPath = found
            case .none:
                state = .disconnected(message: "No Bus Pirate found. Connect the USB cable, then click Connect.")
                return
            case .ambiguous(let ports):
                state = .chooseDevice(ports)
                return
            }
        }
        guard let portPath else { return }
        state = .searching

        let port: POSIXSerialPort
        do {
            port = try POSIXSerialPort(path: portPath)
        } catch TransportError.openFailed(let reason) {
            state = .disconnected(message: "Could not open \(portPath): \(reason). Close other terminal programs that use this port.")
            return
        } catch {
            state = .disconnected(message: "Could not open \(portPath).")
            return
        }

        let newSession = BusPirateSession(transport: port, transcript: transcript)
        do {
            try await newSession.start()
        } catch {
            await newSession.shutdown()
            state = .disconnected(message: "The Bus Pirate did not answer. Disconnect the USB cable, connect it again, then click Connect.")
            return
        }
        session = newSession

        var info: DeviceInfo?
        if let reply = try? await newSession.send("i") {
            info = DeviceInfo.parse(reply)
        }
        if info == nil {
            note = "Connected. Device information was not read."
        } else if info?.commit != DeviceInfo.testedCommit {
            note = "This firmware is different from the tested build (\(DeviceInfo.testedCommit)). Some functions can fail."
        }
        state = .connected(port: portPath, info: info)
        startMonitor(for: newSession)
    }

    func disconnect() async {
        monitor?.cancel()
        monitor = nil
        if let session {
            await session.shutdown()
        }
        session = nil
        note = nil
        state = .disconnected(message: nil)
    }

    func sendLine(_ line: String) async {
        guard let session, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await session.sendInteractive(line)
        } catch SessionError.timeout {
            note = "No reply after 5 seconds."
        } catch {
            deviceWasLost()
        }
    }

    func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript.plainText(), forType: .string)
    }

    func clearConsole() {
        transcript.clear()
    }

    private func startMonitor(for watched: BusPirateSession) {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                if await watched.isDisconnected {
                    self?.deviceWasLost()
                    return
                }
            }
        }
    }

    private func deviceWasLost() {
        guard isConnected else { return }
        monitor?.cancel()
        monitor = nil
        let lost = session
        session = nil
        Task { await lost?.shutdown() }
        note = nil
        state = .disconnected(message: "The Bus Pirate was disconnected.")
    }
}
