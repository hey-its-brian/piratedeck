import Foundation

/// Command text for the read-only actions.
public enum Actions {
    public static let i2cScan = "scan"
    public static let spiFlashProbe = "flash probe"

    private static func hex(_ byte: UInt8) -> String { String(format: "0x%02x", byte) }

    /// Sets the register pointer, then reads `count` bytes (1 to 255).
    public static func i2cRead(address7: UInt8, register: UInt8, count: Int) -> String {
        let write = (address7 & 0x7F) << 1
        let n = min(max(count, 1), 255)
        return "[\(hex(write)) \(hex(register)) [\(hex(write | 1)) r:\(n)]"
    }

    public static func spiTransfer(bytes: [UInt8], readCount: Int) -> String {
        var parts = bytes.map(hex)
        let n = min(max(readCount, 0), 255)
        if n > 0 { parts.append("r:\(n)") }
        return "[" + parts.joined(separator: " ") + "]"
    }

    /// Parses hex bytes such as "9f 00 0x1A" or "9f,00". Returns nil if a token is bad.
    public static func rawBytes(from text: String) -> [UInt8]? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        guard !tokens.isEmpty else { return nil }
        var bytes: [UInt8] = []
        for token in tokens {
            var digits = token.lowercased()
            if digits.hasPrefix("0x") { digits.removeFirst(2) }
            guard !digits.isEmpty, digits.count <= 2, let value = UInt8(digits, radix: 16) else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    /// The result line of a scan, or its error and hint lines.
    public static func scanSummary(_ reply: String) -> String? {
        let lines = collapseCarriageReturns(stripANSI(reply)).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let found = lines.first(where: { $0.hasPrefix("Found ") }) { return found }
        let problems = lines.filter { $0.hasPrefix("Error:") || $0.hasPrefix("Hint:") }
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }
}
