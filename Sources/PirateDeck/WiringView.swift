import SwiftUI
import PirateDeckCore

struct WiringView: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox("Wiring") {
            VStack(alignment: .leading, spacing: 8) {
                if let status = model.status {
                    summary(status)
                    Divider()
                    if !status.pins.isEmpty {
                        pinRows(status)
                    } else if !status.rawPinTable.isEmpty {
                        Text(status.rawPinTable)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Select a mode and click Apply to see the wiring.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No device status.").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Refresh") { Task { await model.refresh() } }
                    .disabled(model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func summary(_ status: DeviceStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mode: \(status.mode)").font(.headline)
            ForEach(status.settings, id: \.key) { setting in
                Text("\(setting.key): \(setting.value)").font(.callout).foregroundStyle(.secondary)
            }
            if let power = status.powerOn {
                if power, let set = status.setVoltage, let measured = status.measuredVoltage {
                    let current = status.currentMilliamps.map { String(format: ", %.1f mA", $0) } ?? ""
                    Text(String(format: "Power supply: ON, set %.1f V, measured %.2f V", set, measured) + current)
                        .font(.callout)
                } else {
                    Text("Power supply: \(power ? "ON" : "OFF")").font(.callout)
                }
            }
            if let pullups = status.pullupsOn {
                Text("Pull-up resistors: \(pullups ? "ON" : "OFF")").font(.callout)
            }
        }
    }

    private func pinRows(_ status: DeviceStatus) -> some View {
        let used = status.pins.filter { $0.label != "-" }
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            GridRow {
                Text("Pin").bold(); Text("Signal").bold(); Text("Connect to").bold(); Text("Voltage").bold()
            }
            ForEach(used, id: \.number) { pin in
                GridRow {
                    Text(pin.name == "Vout" ? "VOUT" : pin.name).font(.system(.body, design: .monospaced))
                    Text(signal(pin))
                    Text(target(pin)).foregroundStyle(.secondary)
                    Text(pin.voltage.map { String(format: "%.1f V", $0) } ?? "")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private func signal(_ pin: PinState) -> String {
        if pin.name == "Vout" { return pin.label == "OFF" ? "supply off" : "supply \(pin.label)" }
        return pin.label
    }

    private func target(_ pin: PinState) -> String {
        switch pin.label {
        case "GND": return "target GND"
        case "TX->": return "target RX"
        case "RX<-": return "target TX"
        default:
            if pin.name == "Vout" { return "target VCC (power or reference)" }
            return "target \(pin.label)"
        }
    }
}
