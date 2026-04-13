import Foundation

/// Listens on a Unix domain socket for Claude Code hook events.
/// Each hook invocation connects, sends one JSON payload, and disconnects.
/// Uses POSIX sockets since Network.framework NWListener doesn't reliably
/// support Unix domain sockets.
final class ClaudeSocketServer {
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var running = false
    private let onEvent: @MainActor (ClaudeEvent) -> Void

    init(socketPath: String = "/tmp/notchi.sock", onEvent: @escaping @MainActor (ClaudeEvent) -> Void) {
        self.socketPath = socketPath
        self.onEvent = onEvent
    }

    func start() {
        removeSocketFile()

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            print("[ClaudeSocket] Failed to create socket: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for i in 0..<min(pathBytes.count, maxLen - 1) {
                buf[i] = UInt8(bitPattern: pathBytes[i])
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("[ClaudeSocket] Failed to bind: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        guard listen(serverFD, 5) == 0 else {
            print("[ClaudeSocket] Failed to listen: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        // Make non-blocking
        let flags = fcntl(serverFD, F_GETFL)
        _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

        running = true
        print("[ClaudeSocket] Listening on \(socketPath)")

        // Accept loop on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        removeSocketFile()
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &clientLen)
                }
            }

            if clientFD >= 0 {
                // Handle each client on its own queue
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.handleClient(clientFD)
                }
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // No pending connections — sleep briefly
                Thread.sleep(forTimeInterval: 0.05)
            } else if running {
                print("[ClaudeSocket] Accept error: \(errno)")
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    // MARK: - Client Handling

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        var data = Data()
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        // Set a read timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        while true {
            let bytesRead = read(fd, buffer, bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                // 0 = EOF, -1 = error/timeout
                break
            }
        }

        guard !data.isEmpty else { return }

        let decoder = JSONDecoder()
        do {
            let event = try decoder.decode(ClaudeEvent.self, from: data)
            let callback = self.onEvent
            Task { @MainActor in
                callback(event)
            }
        } catch {
            print("[ClaudeSocket] Failed to decode: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                print("[ClaudeSocket] Raw: \(raw.prefix(300))")
            }
        }
    }

    // MARK: - Helpers

    private func removeSocketFile() {
        unlink(socketPath)
    }
}
