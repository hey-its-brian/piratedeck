import Foundation

public enum BusMode: String, CaseIterable, Sendable, Identifiable {
    case hiz = "HiZ", i2c = "I2C", spi = "SPI", uart = "UART"
    public var id: String { rawValue }
    /// The command that selects this mode.
    public var command: String { "m " + rawValue.lowercased() }
}

public enum Parity: Int, CaseIterable, Sendable, Identifiable {
    case none = 1, even = 2, odd = 3
    public var id: Int { rawValue }
    public var title: String {
        switch self { case .none: return "None"; case .even: return "Even"; case .odd: return "Odd" }
    }
}

/// The settings of the modes that the app can configure.
public struct ModeSettings: Equatable, Sendable {
    public var i2cSpeedKHz = 400
    public var i2cClockStretching = false

    public var spiSpeedKHz = 100
    public var spiDataBits = 8
    public var spiClockIdleHigh = false
    public var spiTrailingEdge = false
    public var spiCSActiveLow = true

    public var uartBaud = 115200
    public var uartDataBits = 8
    public var uartParity = Parity.none
    public var uartStopBits = 1

    public init() {}

    public func validationErrors(for mode: BusMode) -> [String] {
        var errors: [String] = []
        switch mode {
        case .hiz: break
        case .i2c:
            if !(1...1000).contains(i2cSpeedKHz) { errors.append("I2C speed must be 1 to 1000 kHz.") }
        case .spi:
            if !(1...62500).contains(spiSpeedKHz) { errors.append("SPI speed must be 1 to 62500 kHz.") }
            if !(4...8).contains(spiDataBits) { errors.append("SPI data bits must be 4 to 8.") }
        case .uart:
            if !(300...3_000_000).contains(uartBaud) { errors.append("UART speed must be 300 to 3000000 baud.") }
            if !(5...8).contains(uartDataBits) { errors.append("UART data bits must be 5 to 8.") }
            if !(1...2).contains(uartStopBits) { errors.append("UART stop bits must be 1 or 2.") }
        }
        return errors
    }

    /// The answer for each setup menu, by menu title.
    public func menuAnswers(for mode: BusMode) -> [String: String] {
        switch mode {
        case .hiz:
            return [:]
        case .i2c:
            return ["I2C speed": String(i2cSpeedKHz), "Clock stretching": i2cClockStretching ? "2" : "1"]
        case .spi:
            return ["SPI speed": String(spiSpeedKHz), "Data bits": String(spiDataBits),
                    "Clock polarity": spiClockIdleHigh ? "2" : "1",
                    "Clock phase": spiTrailingEdge ? "2" : "1",
                    "Chip select": spiCSActiveLow ? "2" : "1"]
        case .uart:
            return ["UART speed": String(uartBaud), "Data bits": String(uartDataBits),
                    "Parity": String(uartParity.rawValue), "Stop bits": String(uartStopBits),
                    // Fixed in this version: no flow control, signal not inverted.
                    "Hardware flow control": "1", "Signal inversion": "1"]
        }
    }
}
