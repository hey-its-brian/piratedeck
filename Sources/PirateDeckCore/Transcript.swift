import Foundation

/// A thread-safe log of all text sent to and received from the device.
public final class Transcript: @unchecked Sendable {
    public enum Direction: Sendable { case sent, received }

    private let lock = NSLock()
    private var text = ""
    private var handler: (@Sendable () -> Void)?

    public init() {}

    public var onChange: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); handler = newValue; lock.unlock() }
    }

    public func append(_ direction: Direction, _ chunk: String) {
        lock.lock()
        switch direction {
        case .sent:
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += ">> " + chunk + "\n"
        case .received:
            text += chunk  // raw; codes can be split across chunks, so strip on read
        }
        let callback = handler
        lock.unlock()
        callback?()
    }

    /// Readable text: no escape codes, echo redraws removed.
    public func plainText() -> String {
        collapseCarriageReturns(rawText())
    }

    /// Text without escape codes but with carriage returns kept (for test fixtures).
    public func rawText() -> String {
        lock.lock(); defer { lock.unlock() }
        return stripANSI(text)
    }

    public func clear() {
        lock.lock()
        text = ""
        let callback = handler
        lock.unlock()
        callback?()
    }
}
