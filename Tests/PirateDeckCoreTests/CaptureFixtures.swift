import Foundation

/// Text from the real device capture in `Captures/e9cb31e-power-on.txt`
/// (firmware e9cb31e, 2026-11-23). Carriage returns are kept.
enum CaptureFixtures {
    static let capture: String = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Captures/e9cb31e-power-on.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    /// The device output after the n-th time `command` was sent (0-based),
    /// up to the next sent line.
    static func reply(to command: String, occurrence: Int = 0) -> String {
        let blocks = ("\n" + capture).components(separatedBy: "\n>> ")
        let matches = blocks.filter { $0.hasPrefix(command + "\n") }
        guard occurrence < matches.count else { return "" }
        return String(matches[occurrence].dropFirst(command.count + 1))
    }

    static var iReplyI2CPowered: String { reply(to: "i", occurrence: 0) }
    static var iReplyUARTOff: String { reply(to: "i", occurrence: 1) }
    static var vReplyI2CPowered: String { reply(to: "v", occurrence: 1) }
    static var wOnReply: String { reply(to: "W 3.3") }
    static var pOnReply: String { reply(to: "P") }
    static var scanEmptyReply: String { reply(to: "scan") }
    static var usePreviousI2C: String { reply(to: "m i2c") }

    // From Brian's first transcript (power off, first-time menus).
    static let vReplyI2COff = "\rI2C> v [pin]\r\rI2C> v\r\r\n\r\n1.Vout\t2.IO0\t3.IO1\t4.IO2\t5.IO3\t6.IO4\t7.IO5\t8.IO6\t9.IO7\t10.GND\t\r\nOFF\tSDA\tSCL\t-\t-\t-\t-\t-\t-\tGND\t\r\n0.0V\t0.0V\t0.0V\t0.0V\t0.0V\t0.0V\t0.0V\t0.0V\t0.0V\tGND\r\n\r\nI2C> \u{03}"
    static let scanErrorReply = "\r\nError: No voltage detected on VOUT/VREF pin\r\nHint: Use W to enable power, or attach an external supply\r\n\r\nError: Pull-up not detected on IO pin\r\nHint: Use P to enable pull-up resistors, or use external pull-up\r\n\r\nAborting I2C scan\r\n\r\nI2C> \u{03}"
    static let i2cSpeedMenu = "\rHiZ> m i2c\r\r\n\r\nMode: I2C\rI2C speed\r\n 1kHz to 1000kHz\r\nx to exit (400) > "
    static let clockStretchMenu = "\r\n\r\nClock stretching\r\n 1. OFF*\r\n 2. on\r\nx to exit (1) > "
    static let i2cPrompt = "\r\n\r\n\r\nI2C> \u{03}"
}
