import Foundation

public enum PortChoice: Equatable, Sendable {
    case found(String)
    case none
    case ambiguous([String])
}

/// Selects the Bus Pirate terminal port. The device shows two ports, for example
/// `cu.usbmodem5buspirate1` (terminal) and `cu.usbmodem5buspirate3` (binary).
/// Ports without "buspirate" in the name are never used, because opening the
/// port of a different board (for example an ESP32) can reset that board.
public enum PortFinder {
    public static func terminalPort(from names: [String]) -> PortChoice {
        let matches = names.filter {
            $0.hasPrefix("cu.usbmodem") && $0.range(of: "buspirate", options: .caseInsensitive) != nil
        }
        var groups: [String: [String]] = [:]
        for name in matches {
            groups[String(name.dropLast()), default: []].append(name)
        }
        let firsts = groups.values.compactMap { $0.min() }.sorted().map { "/dev/" + $0 }
        switch firsts.count {
        case 0: return .none
        case 1: return .found(firsts[0])
        default: return .ambiguous(firsts)
        }
    }

    public static func listDevNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
    }
}
