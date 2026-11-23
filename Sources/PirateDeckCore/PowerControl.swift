import Foundation

public struct PowerRequest: Equatable, Sendable {
    public var volts: Double
    public var milliamps: Int
    public init(volts: Double, milliamps: Int) { self.volts = volts; self.milliamps = milliamps }

    public func validationErrors() -> [String] {
        var errors: [String] = []
        if !(0.8...5.0).contains(volts) { errors.append("Voltage must be 0.8 to 5.0 V.") }
        if !(0...500).contains(milliamps) { errors.append("Current limit must be 0 to 500 mA.") }
        return errors
    }

    /// Always an uppercase W. A lowercase w turns the supply off.
    public var command: String {
        "W " + String(format: "%g", volts) + " " + String(milliamps)
    }
}

public enum PowerControl {
    public static let off = "w"
    public static let pullupsOn = "P"
    public static let pullupsOff = "p"

    public static func supplyEnabled(in reply: String) -> Bool {
        collapseCarriageReturns(stripANSI(reply)).firstMatch(of: #/Power supply:\s+Enabled/#) != nil
    }

    /// The firmware undervoltage limit is 10 percent.
    public static func voltageIsGood(set: Double, measured: Double?) -> Bool {
        guard let measured, set > 0 else { return false }
        return abs(measured - set) <= set * 0.10
    }
}
