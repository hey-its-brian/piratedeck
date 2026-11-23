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

    /// For lines typed by a person in the console. Returns at a mode prompt, or
    /// when the output stops for 300 ms (for example at a menu prompt).
    public func sendInteractive(_ line: String, timeout: Duration = .seconds(5)) async throws -> String {
        startReaderIfNeeded()
        try write(line + "\r", logAs: line.isEmpty ? "<Enter>" : line)
        try await waitForQuiet(.milliseconds(300), deadline: ContinuousClock.now + timeout)
        if let mode = modePrompt(in: buffer) {
            currentMode = mode
            return cleaned(buffer, command: line, dropPrompt: true)
        }
        let text = cleaned(buffer, command: line, dropPrompt: false)
        if text.isEmpty { throw SessionError.timeout(partial: "") }
        return text
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

    /// True if the last exchange ended at a mode prompt (not inside a menu).
    public var isAtModePrompt: Bool { modePrompt(in: buffer) != nil }

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
        var text = stripANSI(raw)
        if let command, !command.isEmpty {
            // The firmware prints the line again, sometimes with a completion hint:
            //   "\rHiZ> iflash\r\rHiZ> i\r\n". The reply starts after the last
            //   "<prompt> <command>" line.
            let pattern = "(?:^|[\\r\\n])[A-Za-z0-9-]+> ?" + NSRegularExpression.escapedPattern(for: command) + "[ \\t]*(?=[\\r\\n]|$)"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
               let range = Range(match.range, in: text) {
                text = String(text[range.upperBound...])
            } else {
                let trimmed = text.trimmingCharacters(in: trimSet)
                if trimmed == command || trimmed.hasPrefix(command + "\r\n")
                    || trimmed.hasPrefix(command + "\r") || trimmed.hasPrefix(command + "\n") {
                    text = String(trimmed.dropFirst(command.count))
                }
            }
        }
        text = text.trimmingCharacters(in: trimSet)
        if dropPrompt, let mode = modePrompt(in: text), text.hasSuffix(mode + ">") {
            text = String(text.dropLast(mode.count + 1)).trimmingCharacters(in: trimSet)
        }
        return text
    }
}
