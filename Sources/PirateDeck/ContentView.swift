import SwiftUI
import PirateDeckCore

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var consoleOpen = false
    @State private var inputLine = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBar
            Divider()
            if let note = model.note {
                banner(note)
            }
            ForEach(model.warnings, id: \.self) { warning in
                banner(warning)
            }
            middle
            Divider()
            console
        }
        .frame(minWidth: 860, minHeight: 640)
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.25))
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).lineLimit(1).truncationMode(.middle)
            Spacer()
            if model.isConnected {
                Button("Disconnect") { Task { await model.disconnect() } }
            } else {
                Button("Connect") { Task { await model.connect() } }
                    .disabled(model.state == .searching)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
    }

    private var statusColor: Color {
        switch model.state {
        case .connected: return .green
        case .searching: return .orange
        default: return .gray
        }
    }

    private var statusText: String {
        switch model.state {
        case .disconnected: return "Not connected"
        case .searching: return "Searching..."
        case .chooseDevice: return "More than one Bus Pirate found"
        case .connected(let port, let info):
            guard let info else { return "Connected on \(port)" }
            if let commit = info.commit {
                let date = info.buildDate.map { " (\($0))" } ?? ""
                return "\(info.hardware), firmware \(commit)\(date) on \(port)"
            }
            return "\(info.hardware), firmware \(info.firmware) on \(port)"
        }
    }

    // MARK: - Middle area

    @ViewBuilder
    private var middle: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .disconnected(let message):
                if let message {
                    Text(message).multilineTextAlignment(.center)
                } else {
                    Text("Connect the Bus Pirate with a USB cable, then click Connect.")
                }
            case .chooseDevice(let ports):
                Text("Select the Bus Pirate to use:")
                ForEach(ports, id: \.self) { port in
                    Button(port) { Task { await model.connect(path: port) } }
                }
            case .searching:
                ProgressView()
            case .connected:
                HStack(alignment: .top, spacing: 12) {
                    SetupView(model: model).frame(width: 360)
                    WiringView(model: model)
                }
                ActionsView(model: model)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Console

    private var console: some View {
        DisclosureGroup("Console", isExpanded: $consoleOpen) {
            VStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(model.consoleText.isEmpty ? " " : model.consoleText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(minHeight: 180, idealHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: model.consoleText) {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
                HStack {
                    TextField("Type a command, then press Return", text: $inputLine)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(!model.isConnected || model.isBusy)
                        .onSubmit { submit() }
                    Button("Send") { submit() }
                        .disabled(!model.isConnected || model.isBusy)
                    Button("Copy Transcript") { model.copyTranscript() }
                    Button("Clear") { model.clearConsole() }
                }
            }
            .padding(.top, 6)
        }
        .padding(10)
    }

    private func submit() {
        let line = inputLine
        inputLine = ""
        Task { await model.sendLine(line) }
    }
}
