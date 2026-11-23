import Foundation

public struct Setting: Equatable, Sendable {
    public let key: String
    public let value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
}

/// One column of the pin table that `i` and `v` print.
public struct PinState: Equatable, Sendable {
    public let number: Int
    public let name: String      // "Vout", "IO0" ... "GND"
    public let label: String     // "SDA", "TX->", "-", "OFF", "003.1mA", "GND"
    public let voltage: Double?  // nil for GND
    public init(number: Int, name: String, label: String, voltage: Double?) {
        self.number = number; self.name = name; self.label = label; self.voltage = voltage
    }
}

/// The parsed `i` reply when a mode is active.
public struct DeviceStatus: Equatable, Sendable {
    public let mode: String
    public let settings: [Setting]
    public let pullupsOn: Bool?
    public let powerOn: Bool?
    public let setVoltage: Double?
    public let measuredVoltage: Double?
    public let currentMilliamps: Double?
    public let pins: [PinState]
    public let rawPinTable: String

    /// Returns nil if the text has no "Active mode:" line.
    public static func parse(_ reply: String) -> DeviceStatus? {
        let lines = collapseCarriageReturns(stripANSI(reply)).components(separatedBy: "\n")
        guard let modeIndex = lines.firstIndex(where: { $0.hasPrefix("Active mode:") }) else { return nil }
        let modeText = lines[modeIndex].dropFirst("Active mode:".count).trimmingCharacters(in: .whitespaces)
        let mode = modeText.split(separator: " ").first.map(String.init) ?? ""

        var settings: [Setting] = []
        for line in lines[(modeIndex + 1)...] {
            guard line.hasPrefix(" "), let colon = line.range(of: ": ") else { break }
            let key = line[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            settings.append(Setting(key: key, value: value))
        }

        func value(after prefix: String) -> String? {
            lines.first(where: { $0.hasPrefix(prefix) })
                .map { $0.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) }
        }
        let pullups = value(after: "Pull-up resistors:").map { $0.hasPrefix("ON") }
        let powerText = value(after: "Power supply:")
        let powerOn = powerText.map { $0.hasPrefix("ON") }
        var setVoltage: Double?
        var measured: Double?
        if let powerText, let match = powerText.firstMatch(of: #/\(([0-9.]+)V\/([0-9.]+)V\)/#) {
            setVoltage = Double(match.1)
            measured = Double(match.2)
        }
        var current: Double?
        if let text = value(after: "Current limit:"), let match = text.firstMatch(of: #/\(([0-9.]+)mA/#) {
            current = Double(match.1)
        }
        let table = parsePinTable(reply)
        return DeviceStatus(mode: mode, settings: settings, pullupsOn: pullups, powerOn: powerOn,
                            setVoltage: setVoltage, measuredVoltage: measured, currentMilliamps: current,
                            pins: table.pins, rawPinTable: table.raw)
    }

    /// Parses the three-row pin table. Also used for the `v` reply.
    /// If the rows do not match, `pins` is empty and `raw` has the table text.
    public static func parsePinTable(_ text: String) -> (pins: [PinState], raw: String) {
        let lines = collapseCarriageReturns(stripANSI(text)).components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("1.Vout") }) else { return ([], "") }
        let rows = Array(lines[start...].prefix(3))
        let raw = rows.joined(separator: "\n")
        func cells(_ line: String) -> [String] {
            line.components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard rows.count == 3 else { return ([], raw) }
        let names = cells(rows[0]), labels = cells(rows[1]), volts = cells(rows[2])
        guard names.count >= 2, names.count == labels.count, names.count == volts.count else { return ([], raw) }
        var pins: [PinState] = []
        for index in names.indices {
            let parts = names[index].split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let number = Int(parts[0]) else { return ([], raw) }
            let voltText = volts[index]
            let voltage = voltText.hasSuffix("V") ? Double(voltText.dropLast()) : nil
            pins.append(PinState(number: number, name: String(parts[1]), label: labels[index], voltage: voltage))
        }
        return (pins, raw)
    }
}
