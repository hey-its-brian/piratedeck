import SwiftUI
import PirateDeckCore

struct SetupView: View {
    @Bindable var model: AppModel

    @State private var mode: BusMode = .i2c
    @State private var settings = ModeSettings()
    @State private var busPirateSupplies = true
    @State private var voltageChoice = 3.3      // -1 = Other
    @State private var customVolts = 3.3
    @State private var milliamps = 300
    @State private var pullups = true

    private let voltagePresets: [Double] = [1.8, 2.5, 3.3, 5.0]
    private let baudPresets = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]

    private var volts: Double { voltageChoice < 0 ? customVolts : voltageChoice }

    private var errors: [String] {
        var all = settings.validationErrors(for: mode)
        if mode != .hiz, busPirateSupplies {
            all += PowerRequest(volts: volts, milliamps: milliamps).validationErrors()
        }
        return all
    }

    var body: some View {
        GroupBox("Setup") {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(BusMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: mode) { _, new in pullups = (new == .i2c) }

                modeSettings

                if mode != .hiz {
                    Picker("Power", selection: $busPirateSupplies) {
                        Text("Bus Pirate supplies power").tag(true)
                        Text("Target has its own supply").tag(false)
                    }
                    .pickerStyle(.radioGroup)

                    if busPirateSupplies {
                        Picker("Voltage", selection: $voltageChoice) {
                            ForEach(voltagePresets, id: \.self) { Text(String(format: "%.1f V", $0)).tag($0) }
                            Text("Other").tag(-1.0)
                        }
                        if voltageChoice < 0 {
                            TextField("Voltage (0.8 to 5.0 V)", value: $customVolts, format: .number)
                        }
                        TextField("Current limit (mA)", value: $milliamps, format: .number)
                    } else {
                        Text("Connect the target supply to the VOUT pin. The Bus Pirate uses it as the reference for the IO pins.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Pull-up resistors", isOn: $pullups)
                    if mode == .i2c {
                        Text("I2C needs pull-ups.").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text("HiZ is the safe mode. All outputs are off.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                if let first = errors.first {
                    Text(first).font(.callout).foregroundStyle(.red)
                }

                Button("Apply") {
                    let power: PowerSource = busPirateSupplies
                        ? .busPirate(PowerRequest(volts: volts, milliamps: milliamps))
                        : .target
                    let request = ApplyRequest(mode: mode, settings: settings, power: power, pullups: pullups)
                    Task { await model.apply(request) }
                }
                .disabled(model.isBusy || !errors.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .formStyle(.columns)
            .padding(6)
        }
    }

    @ViewBuilder
    private var modeSettings: some View {
        switch mode {
        case .hiz:
            EmptyView()
        case .i2c:
            TextField("Speed (kHz)", value: $settings.i2cSpeedKHz, format: .number.grouping(.never))
            Toggle("Clock stretching", isOn: $settings.i2cClockStretching)
        case .spi:
            TextField("Speed (kHz)", value: $settings.spiSpeedKHz, format: .number.grouping(.never))
            Stepper("Data bits: \(settings.spiDataBits)", value: $settings.spiDataBits, in: 4...8)
            Picker("Clock idle state", selection: $settings.spiClockIdleHigh) {
                Text("Low").tag(false); Text("High").tag(true)
            }
            Picker("Clock edge", selection: $settings.spiTrailingEdge) {
                Text("Leading").tag(false); Text("Trailing").tag(true)
            }
            Picker("Chip select", selection: $settings.spiCSActiveLow) {
                Text("Active low (/CS)").tag(true); Text("Active high (CS)").tag(false)
            }
        case .uart:
            Picker("Baud", selection: $settings.uartBaud) {
                ForEach(baudPresets, id: \.self) { Text(String($0)).tag($0) }
            }
            Stepper("Data bits: \(settings.uartDataBits)", value: $settings.uartDataBits, in: 5...8)
            Picker("Parity", selection: $settings.uartParity) {
                ForEach(Parity.allCases) { Text($0.title).tag($0) }
            }
            Stepper("Stop bits: \(settings.uartStopBits)", value: $settings.uartStopBits, in: 1...2)
        }
    }
}
