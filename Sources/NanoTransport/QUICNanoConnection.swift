// QUICNanoConnection — a Nano transport backed by a single bidirectional QUIC
// stream over Apple's Network.framework.
//
// QUIC (TLS 1.3, multiplexed, 0-RTT-capable) is the vendor's direct media
// transport. Here we open one QUIC connection carrying one bidirectional
// stream and frame application messages with `NanoFraming`. A richer build can
// move to an `NWMultiplexGroup` for multiple streams (control vs media); one
// stream is enough to carry the mirroring byte stream end to end.
//
// SPDX-License-Identifier: MIT

#if canImport(Network)
import Foundation
import Network
import Security
import CryptoKit

public struct QUICNanoConfig {
    public var host: String
    public var port: UInt16
    /// ALPN protocol identifiers to offer. Must match what the peer expects.
    public var alpn: [String]
    /// Skip server-certificate verification (direct peer uses a self-signed /
    /// device-trust cert, not a web PKI chain). Default true for the P2P path.
    public var allowInsecureCertificates: Bool
    /// If set, pin the peer's leaf certificate to this SHA-256 (DER). Takes
    /// precedence over `allowInsecureCertificates`: the handshake succeeds only
    /// when the presented leaf hashes to this value.
    public var pinnedCertificateSHA256: Data?
    /// Idle timeout in milliseconds.
    public var idleTimeoutMs: Int

    public init(host: String,
                port: UInt16,
                alpn: [String] = ["nano"],
                allowInsecureCertificates: Bool = true,
                pinnedCertificateSHA256: Data? = nil,
                idleTimeoutMs: Int = 30_000) {
        self.host = host
        self.port = port
        self.alpn = alpn
        self.allowInsecureCertificates = allowInsecureCertificates
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256
        self.idleTimeoutMs = idleTimeoutMs
    }
}

@available(macOS 12.0, *)
public final class QUICNanoConnection: NanoTransport {
    public private(set) var state: NanoConnectionState = .idle {
        didSet { queue.async { [state, onStateChange] in onStateChange?(state) } }
    }
    public var onFrame: ((Data) -> Void)?
    public var onStateChange: ((NanoConnectionState) -> Void)?

    private let config: QUICNanoConfig
    private let queue = DispatchQueue(label: "nano.quic")
    private var connection: NWConnection?
    private var decoder = NanoFrameDecoder()

    public init(config: QUICNanoConfig) {
        self.config = config
    }

    public func start() {
        state = .connecting
        let options = NWProtocolQUIC.Options(alpn: config.alpn)
        options.idleTimeout = config.idleTimeoutMs
        // QUIC mandates TLS 1.3; configure the sec_protocol layer.
        let sec = options.securityProtocolOptions
        if let pinned = config.pinnedCertificateSHA256 {
            sec_protocol_options_set_verify_block(sec, { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                complete(Self.leafMatches(secTrust, sha256: pinned))
            }, queue)
        } else if config.allowInsecureCertificates {
            sec_protocol_options_set_verify_block(sec, { _, _, complete in
                // Direct peer presents a device-trust cert, not a web chain.
                complete(true)
            }, queue)
        }
        let params = NWParameters(quic: options)
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(config.host),
            port: NWEndpoint.Port(rawValue: config.port) ?? .any
        )
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in self?.handle(st) }
        conn.start(queue: queue)
    }

    private func handle(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            state = .ready
            receiveLoop()
        case .waiting(let err):
            state = .failed("waiting: \(err)")
        case .failed(let err):
            state = .failed(String(describing: err))
        case .cancelled:
            state = .cancelled
        default:
            break
        }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try self.decoder.push(data) { self.onFrame?(frame) }
                } catch {
                    self.state = .failed(String(describing: error))
                    self.connection?.cancel()
                    return
                }
            }
            if let error = error {
                self.state = .failed(String(describing: error))
                return
            }
            if isComplete {
                self.connection?.cancel()
                return
            }
            self.receiveLoop()
        }
    }

    public func send(_ payload: Data) {
        guard state == .ready else { return }
        let framed: Data
        do { framed = try NanoFraming.encode(payload) }
        catch { state = .failed(String(describing: error)); return }
        connection?.send(content: framed, completion: .contentProcessed { [weak self] error in
            if let error = error { self?.state = .failed(String(describing: error)) }
        })
    }

    public func cancel() {
        connection?.cancel()
        connection = nil
    }

    /// True when the trust's leaf certificate's DER SHA-256 equals `sha256`.
    static func leafMatches(_ trust: SecTrust, sha256: Data) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return false }
        let der = SecCertificateCopyData(leaf) as Data
        let digest = Data(SHA256.hash(data: der))
        return digest == sha256
    }
}
#endif
