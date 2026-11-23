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

    // Plan 2 state
    var status: DeviceStatus?
    var warnings: [String] = []
    var actionsEnabled = false
    var actionTitle = ""
    var actionSummary: String?
    var actionResult = ""

    private let transcript = Transcript()
    private var session: BusPirateSession?
    private var controller: DeviceController?
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

    /// The active mode on the device, if the app knows it.
    var activeMode: BusMode? {
        guard let mode = status?.mode else { return nil }
        return BusMode.allCases.first { $0.rawValue.lowercased() == mode.lowercased() }
    }

    // MARK: - Connection

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
        controller = DeviceController(session: newSession)

        var info: DeviceInfo?
        if let reply = try? await newSession.send("i") {
            info = DeviceInfo.parse(reply)
            status = DeviceStatus.parse(reply)
        }
        if info == nil {
            note = "Connected. Device information was not read."
        } else if info?.commit != DeviceInfo.testedCommit {
            note = "This firmware is different from the tested build (\(DeviceInfo.testedCommit)). Some functions can fail."
        }
        // The app did not apply this setup, so it does not know if it is safe.
        actionsEnabled = false
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
        controller = nil
        clearDeviceState()
        note = nil
        state = .disconnected(message: nil)
    }

    // MARK: - Setup and actions

    func apply(_ request: ApplyRequest) async {
        guard let controller, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        warnings = []
        actionsEnabled = false
        actionSummary = nil
        actionResult = ""
        actionTitle = ""
        do {
            let result = try await controller.apply(request)
            warnings = result.warnings
            actionsEnabled = result.actionsEnabled
            // HiZ returns no status. Read it so the screen shows the mode.
            status = request.mode == .hiz ? try await controller.refresh() : result.status
        } catch SessionError.timeout {
            warnings = ["The Bus Pirate did not answer in time. Open the console to see the last reply."]
        } catch is ConfigError {
            warnings = ["The mode change did not complete. Open the console to see the last reply."]
        } catch {
            deviceWasLost()
        }
    }

    func returnToHiZ() async {
        await apply(ApplyRequest(mode: .hiz, settings: ModeSettings(), power: .target, pullups: false))
    }

    func refresh() async {
        guard let controller, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let fresh = try await controller.refresh() { status = fresh }
        } catch SessionError.timeout {
            warnings = ["The Bus Pirate did not answer in time. Open the console to see the last reply."]
        } catch {
            deviceWasLost()
        }
    }

    func runAction(title: String, command: String, summarize: ((String) -> String?)? = nil) async {
        guard let controller, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        actionTitle = title + "   (command: " + command + ")"
        actionSummary = nil
        actionResult = ""
        do {
            let reply = try await controller.run(command)
            actionResult = collapseCarriageReturns(reply)
            actionSummary = summarize?(reply)
        } catch SessionError.timeout(let partial) {
            actionResult = collapseCarriageReturns(partial)
            actionSummary = "No prompt after 10 seconds. The reply can be incomplete."
        } catch {
            deviceWasLost()
        }
    }

    // MARK: - Console

    func sendLine(_ line: String) async {
        guard let session, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await session.sendInteractive(line)
            // A typed command can change the setup. The app no longer knows if it is safe.
            actionsEnabled = false
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

    // MARK: - Internals

    private func clearDeviceState() {
        status = nil
        warnings = []
        actionsEnabled = false
        actionTitle = ""
        actionSummary = nil
        actionResult = ""
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
        controller = nil
        Task { await lost?.shutdown() }
        clearDeviceState()
        note = nil
        state = .disconnected(message: "The Bus Pirate was disconnected.")
    }
}
