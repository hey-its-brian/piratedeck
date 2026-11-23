import SwiftUI
import PirateDeckCore

struct ActionsView: View {
    @Bindable var model: AppModel

    @State private var i2cAddress = "50"
    @State private var i2cRegister = "00"
    @State private var i2cCount = 8
    @State private var spiBytes = "9f"
    @State private var spiReadCount = 3

    private var canRun: Bool { model.actionsEnabled && !model.isBusy }

    var body: some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    modeActions
                    Spacer()
                    Button("Return to HiZ") { Task { await model.returnToHiZ() } }
                        .disabled(model.isBusy)
                }
                if !model.actionsEnabled, model.activeMode != nil, model.activeMode != .hiz {
                    Text("Click Apply in Setup to enable the actions.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !model.actionTitle.isEmpty {
                    Text(model.actionTitle).font(.callout).foregroundStyle(.secondary)
                }
                if let summary = model.actionSummary {
                    Text(summary).bold().textSelection(.enabled)
                }
                if !model.actionResult.isEmpty {
                    ScrollView {
                        Text(model.actionResult)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    @ViewBuilder
    private var modeActions: some View {
        switch model.activeMode {
        case .i2c:
            Button("Scan bus") {
                Task { await model.runAction(title: "Scan bus", command: Actions.i2cScan, summarize: Actions.scanSummary) }
            }
            .disabled(!canRun)
            Divider().frame(height: 20)
            Text("Address 0x")
            TextField("50", text: $i2cAddress).frame(width: 44)
            Text("Register 0x")
            TextField("00", text: $i2cRegister).frame(width: 44)
            Stepper("Count: \(i2cCount)", value: $i2cCount, in: 1...255)
            Button("Read register") {
                guard let address = UInt8(i2cAddress, radix: 16), address < 0x80,
                      let register = UInt8(i2cRegister, radix: 16) else { return }
                let command = Actions.i2cRead(address7: address, register: register, count: i2cCount)
                Task { await model.runAction(title: "Read register", command: command) }
            }
            .disabled(!canRun || !i2cFieldsAreValid)
        case .spi:
            Button("Identify flash chip") {
                Task { await model.runAction(title: "Identify flash chip", command: Actions.spiFlashProbe) }
            }
            .disabled(!canRun)
            Divider().frame(height: 20)
            Text("Bytes (hex)")
            TextField("9f", text: $spiBytes).frame(width: 140)
            Stepper("Read: \(spiReadCount)", value: $spiReadCount, in: 0...255)
            Button("Send bytes") {
                guard let bytes = Actions.rawBytes(from: spiBytes) else { return }
                let command = Actions.spiTransfer(bytes: bytes, readCount: spiReadCount)
                Task { await model.runAction(title: "Send bytes", command: command) }
            }
            .disabled(!canRun || Actions.rawBytes(from: spiBytes) == nil)
        case .uart:
            Text("Use the console to send data. Type { to open the port and show incoming data.")
                .foregroundStyle(.secondary)
        case .hiz, .none:
            Text("Select a mode in Setup and click Apply.")
                .foregroundStyle(.secondary)
        }
    }

    private var i2cFieldsAreValid: Bool {
        guard let address = UInt8(i2cAddress, radix: 16), address < 0x80 else { return false }
        return UInt8(i2cRegister, radix: 16) != nil
    }
}
