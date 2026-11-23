import Foundation

public enum TransportError: Error, Equatable {
    case openFailed(String)
    case writeFailed
    case closed
}

/// A byte pipe to the device. The `incoming` stream finishes when the device
/// disconnects or `close()` is called.
public protocol ByteTransport: AnyObject, Sendable {
    func write(_ data: Data) throws
    var incoming: AsyncStream<Data> { get }
    func close()
}
