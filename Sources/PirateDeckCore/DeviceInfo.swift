import Foundation

/// The parsed reply of the `i` command.
public struct DeviceInfo: Equatable, Sendable {
    public let hardware: String
    public let firmware: String
    public let commit: String?
    public let buildDate: String?
    public let modes: [String]
    public let raw: String

    /// The firmware commit that this app was tested with.
    public static let testedCommit = "e9cb31e"

    /// Returns nil if the text is not a Bus Pirate `i` reply.
    public static func parse(_ reply: String) -> DeviceInfo? {
        let lines = stripANSI(reply)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let hardware = lines.first(where: { $0.hasPrefix("Bus Pirate") }) else { return nil }

        var firmware = ""
        if let line = lines.first(where: { $0.hasPrefix("Firmware ") }) {
            firmware = String(line.dropFirst("Firmware ".count))
        }
        var commit: String?
        var buildDate: String?
        if let match = firmware.firstMatch(of: #/@ ([0-9a-f]{6,40})(?: \((.+)\))?/#) {
            commit = String(match.1)
            buildDate = match.2.map(String.init)
        }
        var modes: [String] = []
        if let line = lines.first(where: { $0.hasPrefix("Available modes:") }) {
            modes = line.dropFirst("Available modes:".count)
                .split(separator: " ").map(String.init)
        }
        return DeviceInfo(hardware: hardware, firmware: firmware, commit: commit,
                          buildDate: buildDate, modes: modes, raw: reply)
    }
}
