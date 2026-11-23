import Foundation
@testable import PirateDeckCore

final class FakeTransport: ByteTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _written: [String] = []
    private var _closed = false
    private var continuation: AsyncStream<Data>.Continuation!
    let incoming: AsyncStream<Data>
    var autoReplies: [String: String] = [:]

    init() {
        var c: AsyncStream<Data>.Continuation!
        incoming = AsyncStream { c = $0 }
        continuation = c
    }

    var written: [String] {
        lock.lock(); defer { lock.unlock() }
        return _written
    }

    func write(_ data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        if _closed { lock.unlock(); throw TransportError.closed }
        _written.append(text)
        let reply = autoReplies[text]
        lock.unlock()
        if let reply { feed(reply) }
    }

    func feed(_ text: String) {
        continuation.yield(Data(text.utf8))
    }

    func disconnect() {
        lock.lock(); _closed = true; lock.unlock()
        continuation.finish()
    }

    func close() { disconnect() }
}
