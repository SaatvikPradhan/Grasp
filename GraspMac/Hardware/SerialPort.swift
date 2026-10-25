import Darwin
import Foundation

/// One USB serial device at 115200 baud, read a line at a time on a background queue.
/// Lines and the close notice arrive on the main thread, in order. No third-party code: plain POSIX.
final class SerialPort: @unchecked Sendable {
    let path: String

    private let fd: Int32
    private let queue: DispatchQueue
    private let source: DispatchSourceRead
    private let onLine: @MainActor (String) -> Void
    private let onClose: @MainActor () -> Void
    // Only touched on `queue`.
    private var buffer: [UInt8] = []
    private var closed = false

    /// Opens the device, or returns nil if it can't be opened as a serial port.
    init?(path: String, onLine: @escaping @MainActor (String) -> Void, onClose: @escaping @MainActor () -> Void) {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else {
            Darwin.close(fd)
            return nil
        }
        cfmakeraw(&settings)
        _ = cfsetspeed(&settings, speed_t(B115200))
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(fd, TCSANOW, &settings) == 0 else {
            Darwin.close(fd)
            return nil
        }
        _ = tcflush(fd, TCIOFLUSH)

        self.path = path
        self.fd = fd
        self.onLine = onLine
        self.onClose = onClose
        queue = DispatchQueue(label: "grasp.serial.\(path)")
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    /// Sends a command line, such as one from `ProbeProtocol`.
    func write(_ text: String) {
        let bytes = Array(text.utf8)
        queue.async { [self] in
            guard !closed else { return }
            bytes.withUnsafeBufferPointer { _ = Darwin.write(fd, $0.baseAddress, $0.count) }
        }
    }

    /// Closes the port. `onClose` isn't called for a close you asked for.
    func close() {
        queue.async { [self] in shutDown(notify: false) }
    }

    private func readAvailable() {
        let capacity = 1024
        var chunk = [UInt8](repeating: 0, count: capacity)
        let count = Darwin.read(fd, &chunk, capacity)
        if count > 0 {
            buffer.append(contentsOf: chunk[0..<count])
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<end], as: UTF8.self)
                buffer.removeSubrange(...end)
                let onLine = onLine
                DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
            }
            if buffer.count > 4096 { buffer.removeAll() }   // no newline in 4 KB: not our board
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
            shutDown(notify: true)                          // unplugged
        }
    }

    private func shutDown(notify: Bool) {
        guard !closed else { return }
        closed = true
        source.cancel()                                     // the cancel handler closes the descriptor
        if notify {
            let onClose = onClose
            DispatchQueue.main.async { MainActor.assumeIsolated { onClose() } }
        }
    }
}
