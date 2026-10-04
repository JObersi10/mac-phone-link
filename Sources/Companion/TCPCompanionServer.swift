import Foundation
import Network

/// The Mac-side companion transport. The Mac is the **server** (AirSync-style):
/// it listens on a TCP port, the phone scans the pairing QR and connects, and
/// every frame is `base64( AES-GCM(nonce||ct||tag) )` terminated by `\n`.
///
/// Framing rationale: we own both ends, so a newline-delimited stream of
/// base64 ciphertext lines is enough — no need for a WebSocket dependency. The
/// inner plaintext is exactly the `{id,type,body}` JSON line `CompanionClient`
/// already speaks, so decryption hands a line straight to `handle(line:)`.
public final class TCPCompanionServer: CompanionTransport {
    private let crypto: CompanionCrypto
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "phonelink.companion.server")
    private var inbound = Data()

    /// Plaintext JSON line received from the phone (newline stripped).
    public var onLine: ((Data) -> Void)?
    /// Connection state changes, delivered on the main queue.
    public var onConnected: ((Bool) -> Void)?

    public private(set) var listeningPort: UInt16?

    public init(crypto: CompanionCrypto) {
        self.crypto = crypto
    }

    /// Start listening. Pass `0` to let the OS pick a free port (read it back
    /// from `listeningPort` once started).
    public func start(preferredPort: UInt16 = 0) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        if preferredPort != 0, let port = NWEndpoint.Port(rawValue: preferredPort) {
            listener = try NWListener(using: params, on: port)
        } else {
            listener = try NWListener(using: params)
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.listeningPort = listener.port?.rawValue
            }
        }
        listener.newConnectionHandler = { [weak self] newConn in
            self?.accept(newConn)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        listeningPort = nil
    }

    // MARK: - Connection handling

    private func accept(_ newConn: NWConnection) {
        // One phone at a time: a new connection replaces the old.
        connection?.cancel()
        connection = newConn
        inbound.removeAll(keepingCapacity: true)

        newConn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.notifyConnected(true)
                self?.receiveLoop()
            case .failed, .cancelled:
                self?.notifyConnected(false)
                if self?.connection === newConn { self?.connection = nil }
            default:
                break
            }
        }
        newConn.start(queue: queue)
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.inbound.append(data)
                self.drainLines()
            }
            if isComplete || error != nil {
                self.notifyConnected(false)
                self.connection?.cancel()
                self.connection = nil
                return
            }
            self.receiveLoop()
        }
    }

    /// Split the inbound buffer on `\n`, decrypt each complete frame, and hand
    /// the plaintext JSON line to `onLine`.
    private func drainLines() {
        while let nl = inbound.firstIndex(of: 0x0a) {
            let frame = inbound.subdata(in: inbound.startIndex..<nl)
            inbound.removeSubrange(inbound.startIndex...nl)
            guard !frame.isEmpty, let base64 = String(data: frame, encoding: .utf8) else { continue }
            guard let plaintext = try? crypto.openFromBase64(base64.trimmingCharacters(in: .whitespaces))
            else { continue } // drop undecryptable frames rather than crash
            onLine?(plaintext)
        }
    }

    private func notifyConnected(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onConnected?(connected) }
    }

    // MARK: - CompanionTransport

    /// `line` is a newline-terminated plaintext JSON frame from `CompanionClient`.
    /// We strip the newline, seal it, base64 it, and send `base64\n`.
    public func send(_ line: Data) async throws {
        guard let connection else { throw CompanionTransportError.notConnected }
        var plaintext = line
        if plaintext.last == 0x0a { plaintext.removeLast() }
        let base64 = try crypto.sealToBase64(plaintext)
        var out = Data(base64.utf8)
        out.append(0x0a)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: out, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }
}

public enum CompanionTransportError: Error, Equatable {
    case notConnected
}

// MARK: - Local network address

public enum LocalNetwork {
    /// Best-guess LAN IPv4 address for the QR code (first non-loopback en*/bridge
    /// interface). Returns nil if only loopback is available.
    public static func primaryIPv4Address() -> String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, addr: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                                nil, 0, NI_NUMERICHOST)
            guard r == 0 else { continue }
            let addr = String(cString: host)
            if addr == "127.0.0.1" { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            candidates.append((name, addr))
        }
        // Prefer Wi-Fi/Ethernet (en*) over virtual/bridge interfaces.
        result = candidates.first(where: { $0.name.hasPrefix("en") })?.addr ?? candidates.first?.addr
        return result
    }
}
