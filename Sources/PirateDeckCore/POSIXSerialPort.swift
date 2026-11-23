import Foundation
import Darwin

/// A serial port opened with POSIX termios: raw mode, 8N1, exclusive access.
public final class POSIXSerialPort: ByteTransport, @unchecked Sendable {
    public let incoming: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    public init(path: String, baud: speed_t = 115200) throws {
        let descriptor = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw TransportError.openFailed(String(cString: strerror(errno)))
        }
        // Back to blocking mode after the open.
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK)

        var settings = termios()
        guard tcgetattr(descriptor, &settings) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw TransportError.openFailed(message)
        }
        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE)
        settings.c_cflag |= tcflag_t(CS8)
        settings.c_cc.16 = 1   // VMIN
        settings.c_cc.17 = 0   // VTIME
        _ = cfsetspeed(&settings, baud)
        guard tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw TransportError.openFailed(message)
        }
        _ = ioctl(descriptor, TIOCEXCL)

        fd = descriptor
        var c: AsyncStream<Data>.Continuation!
        incoming = AsyncStream { c = $0 }
        continuation = c

        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "PirateDeck serial reader"
        thread.start()
    }

    deinit { close() }

    public func write(_ data: Data) throws {
        lock.lock()
        let isClosed = closed
        lock.unlock()
        if isClosed { throw TransportError.closed }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw TransportError.writeFailed
                }
                offset += n
            }
        }
    }

    public func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        guard !wasClosed else { return }
        Darwin.close(fd)
        continuation.finish()
    }

    private var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !isClosed {
            // select() with a short timeout, so close() can stop this thread.
            var readSet = fd_set()
            let descriptor = fd
            withUnsafeMutablePointer(to: &readSet) {
                $0.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
                    bits[Int(descriptor / 32)] |= Int32(bitPattern: UInt32(1) << UInt32(descriptor % 32))
                }
            }
            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
            let ready = select(fd + 1, &readSet, nil, nil, &timeout)
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                continuation.yield(Data(buffer[0..<n]))
            } else if n < 0 && (errno == EINTR || errno == EAGAIN) {
                continue
            } else {
                break   // 0 bytes or an error: the device is gone
            }
        }
        close()
    }
}
