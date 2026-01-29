import Foundation

class DaemonServer {
    private let onFileReceived: (String) -> Void
    private var listener: Thread?
    private var socketPath: String?
    private var serverSocket: Int32 = -1
    private var running = false

    init(onFileReceived: @escaping (String) -> Void) {
        self.onFileReceived = onFileReceived
    }

    /// Try to send a file path to a running daemon
    static func sendToDaemon(filePath: String) -> Bool {
        guard let socketPath = Self.getSocketPath() else { return false }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else { return false }

        let data = filePath.data(using: .utf8)!
        let writeResult = data.withUnsafeBytes { ptr in
            Darwin.write(sock, ptr.baseAddress!, data.count)
        }

        return writeResult > 0
    }

    func start() {
        guard let path = Self.getSocketPath() else {
            print("DaemonServer: Could not determine socket path")
            return
        }
        socketPath = path

        // Remove old socket
        unlink(path)

        // Create parent directories
        let parentDir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Create Unix domain socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("DaemonServer: Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("DaemonServer: Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverSocket)
            serverSocket = -1
            return
        }

        guard listen(serverSocket, 5) == 0 else {
            print("DaemonServer: Failed to listen on socket")
            close(serverSocket)
            serverSocket = -1
            return
        }

        running = true

        // Accept connections on background thread
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.qualityOfService = .utility
        thread.name = "GlanceDaemonServer"
        thread.start()
        self.listener = thread
    }

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientLen)
                }
            }

            guard clientSocket >= 0 else {
                if running {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                continue
            }

            // Read file path from client
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientSocket, &buffer, buffer.count)
            close(clientSocket)

            guard bytesRead > 0 else { continue }

            let filePathStr = String(bytes: buffer[0..<bytesRead], encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !filePathStr.isEmpty else { continue }

            // Validate file
            let filePath = URL(fileURLWithPath: filePathStr)
            guard FileManager.default.fileExists(atPath: filePath.path) else {
                print("DaemonServer: File not found: \(filePathStr)")
                continue
            }

            let ext = filePath.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" || ext == "puml" || ext == "plantuml" else {
                print("DaemonServer: Invalid file type: \(ext)")
                continue
            }

            // Resolve to canonical path
            let resolved = filePath.standardized.path

            onFileReceived(resolved)
        }
    }

    func stop() {
        running = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        if let path = socketPath {
            unlink(path)
        }
    }

    static func getSocketPath() -> String? {
        // Match Rust: ~/Library/Caches/com.glance.glance/glance.sock on macOS
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheDir.appendingPathComponent("com.glance.glance/glance.sock").path
    }

    deinit {
        stop()
    }
}
