import Foundation

public enum PowerSource: Equatable, Sendable {
    /// The Bus Pirate supplies power to the target.
    case busPirate(PowerRequest)
    /// The target has its own supply, connected to VOUT/VREF. The app never sends `W`.
    case target
}

public struct ApplyRequest: Equatable, Sendable {
    public var mode: BusMode
    public var settings: ModeSettings
    public var power: PowerSource
    public var pullups: Bool
    public init(mode: BusMode, settings: ModeSettings, power: PowerSource, pullups: Bool) {
        self.mode = mode; self.settings = settings; self.power = power; self.pullups = pullups
    }
}

public struct ApplyResult: Equatable, Sendable {
    public let status: DeviceStatus?
    public let warnings: [String]
    public let actionsEnabled: Bool
}

/// The high-level operations of the app: apply a setup, refresh the status, run an action.
public actor DeviceController {
    private let session: BusPirateSession

    public init(session: BusPirateSession) {
        self.session = session
    }

    public func apply(_ request: ApplyRequest) async throws -> ApplyResult {
        // 1. Safe state first: supply off, pull-ups off.
        // In HiZ both are off already, and the firmware rejects the commands.
        if await session.currentMode?.lowercased() != "hiz" {
            _ = try await session.send(PowerControl.off)
            _ = try await session.send(PowerControl.pullupsOff)
        }

        // 2. Mode and its settings.
        var warnings: [String] = []
        let unknown = try await ModeConfigurator.enter(request.mode, settings: request.settings, session: session)
        if !unknown.isEmpty {
            warnings.append("The app did not know these settings and used the defaults: \(unknown.joined(separator: ", ")).")
        }
        // 3. HiZ has no power and no pull-ups.
        if request.mode == .hiz {
            return ApplyResult(status: nil, warnings: warnings, actionsEnabled: false)
        }

        // 4. Power. Only the Bus Pirate source sends W.
        var supplyEnabled = false
        if case .busPirate(let power) = request.power {
            let reply = try await session.send(power.command, timeout: .seconds(5))
            supplyEnabled = PowerControl.supplyEnabled(in: reply)
        }

        // 5. Pull-ups.
        if request.pullups {
            let reply = try await session.send(PowerControl.pullupsOn)
            if reply.contains("Warning:") {
                warnings.append("Pull-ups are on, but no voltage is present.")
            }
        }

        // 6. Read the result and decide if the actions are safe.
        let status = try await refresh()
        var actionsEnabled = true
        guard let status else {
            warnings.append("The device status was not read. See the console.")
            if case .busPirate = request.power { actionsEnabled = supplyEnabled }
            return ApplyResult(status: nil, warnings: warnings, actionsEnabled: actionsEnabled)
        }
        let vout = status.measuredVoltage ?? status.pins.first?.voltage
        switch request.power {
        case .busPirate(let power):
            if !supplyEnabled || !PowerControl.voltageIsGood(set: power.volts, measured: vout) {
                let shown = vout.map { String(format: "%g", $0) } ?? "unknown"
                warnings.append("VOUT is \(shown) V but the set value is \(String(format: "%g", power.volts)) V. Check for a short circuit. The actions are disabled.")
                actionsEnabled = false
            }
        case .target:
            if (status.pins.first?.voltage ?? 0) < 0.8 {
                warnings.append("No voltage on VOUT/VREF. Connect the target supply to the VOUT pin. The actions are disabled.")
                actionsEnabled = false
            }
        }
        return ApplyResult(status: status, warnings: warnings, actionsEnabled: actionsEnabled)
    }

    /// Sends `i` and parses the reply. Returns nil if the reply did not parse.
    public func refresh() async throws -> DeviceStatus? {
        DeviceStatus.parse(try await session.send("i"))
    }

    /// Runs one command (an action) and returns the reply.
    public func run(_ command: String, timeout: Duration = .seconds(10)) async throws -> String {
        try await session.send(command, timeout: timeout)
    }
}
