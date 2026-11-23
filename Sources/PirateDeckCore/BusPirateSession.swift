import Foundation

public enum SessionError: Error, Equatable {
    case timeout(partial: String)
    case disconnected
}

/// One conversation with the Bus Pirate text console.
/// Sends one line at a time and reads until the mode prompt (for example "HiZ>").
public actor BusPirateSession {
    private let transport: ByteTransport
    private let transcript: Transcript
    private var buffer = ""
    private var lastByteAt = ContinuousClock.now
    private var ended = false
    private var reader: Task<Void, Never>?

    public private(set) var currentMode: String?

    public init(transport: ByteTransport, transcript: Transcript) {
        self.transport = transport
        self.transcript = transcript
    }

    // MARK: - Public API

    /// Gets the device to a mode prompt. Answers the VT100 question with "n"
    /// and leaves a menu with "x".
    public func start(timeout: Duration = .seconds(3)) async throws {
        startReaderIfNeeded()
        let deadline = ContinuousClock.now + timeout
        var key = "\r"
        for _ in 0..<4 {
            try write(key, logAs: key == "\r" ? "<Enter>" : String(key.dropLast()))
            try await waitForQuiet(.milliseconds(300), deadline: deadline)
            if let mode = modePrompt(in: buffer) {
                currentMode = mode
                return
            }
            if ContinuousClock.now >= deadline { break }
            if isVT100Question(buffer) {
                key = "n\r"
            } else if !buffer.isEmpty {
                key = "x\r"
            } else {
                key = "\r"
            }
        }
        throw SessionError.timeout(partial: cleaned(buffer, command: nil, dropPrompt: false))
    }

    /// Sends one command line and returns the reply without the echo and the prompt.
    public func send(_ line: String, timeout: Duration = .seconds(3)) async throws -> String {
        startReaderIfNeeded()
        try write(line + "\r", logAs: line)
        let deadline = ContinuousClock.now + timeout
        while true {
            if let mode = modePrompt(in: buffer),
               ContinuousClock.now - lastByteAt >= .milliseconds(40) {
                currentMode = mode
                return cleaned(buffer, command: line, dropPrompt: true)
            }
            if ended { throw SessionError.disconnected }
            if ContinuousClock.now >= deadline {
                throw SessionError.timeout(partial: cleaned(buffer, command: line, dropPrompt: false))
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Sets HiZ mode if a different mode is active, then closes the port.
    public func shutdown() async {
        if let mode = currentMode, mode.lowercased() != "hiz", !ended {
            _ = try? await send("m hiz", timeout: .seconds(1))
        }
        transport.close()
        reader?.cancel()
        reader = nil
        ended = true
    }

    public var isDisconnected: Bool { ended }

    // MARK: - Internals

    private func startReaderIfNeeded() {
        guard reader == nil, !ended else { return }
        let stream = transport.incoming
        reader = Task { [weak self] in
            for await chunk in stream {
                await self?.received(chunk)
            }
            await self?.streamEnded()
        }
    }

    private func received(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        buffer += text
        lastByteAt = .now
        transcript.append(.received, text)
    }

    private func streamEnded() {
        ended = true
    }

    private func write(_ text: String, logAs label: String) throws {
        if ended { throw SessionError.disconnected }
        buffer = ""
        transcript.append(.sent, label)
        do {
            try transport.write(Data(text.utf8))
        } catch {
            ended = true
            throw SessionError.disconnected
        }
    }

    /// Waits until bytes arrived and then stopped for `quiet`, or until the deadline.
    private func waitForQuiet(_ quiet: Duration, deadline: ContinuousClock.Instant) async throws {
        while ContinuousClock.now < deadline {
            if ended { throw SessionError.disconnected }
            if !buffer.isEmpty {
                if modePrompt(in: buffer) != nil, ContinuousClock.now - lastByteAt >= .milliseconds(40) { return }
                if ContinuousClock.now - lastByteAt >= quiet { return }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func cleaned(_ raw: String, command: String?, dropPrompt: Bool) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines
        var text = stripANSI(raw).trimmingCharacters(in: trimSet)
        if let command, !command.isEmpty,
           text == command || text.hasPrefix(command + "\r\n") || text.hasPrefix(command + "\r") || text.hasPrefix(command + "\n") {
            text = String(text.dropFirst(command.count)).trimmingCharacters(in: trimSet)
        }
        if dropPrompt, let mode = modePrompt(in: text), text.hasSuffix(mode + ">") {
            text = String(text.dropLast(mode.count + 1)).trimmingCharacters(in: trimSet)
        }
        return text
    }
}
