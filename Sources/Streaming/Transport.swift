import Foundation
import Network

/// A single TCP connection to the adb-forwarded local port that scrcpy-server
/// listens on. Thin async wrapper over `NWConnection`.
public final class SocketConnection {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "phonelink.socket")

    public init(host: String = "127.0.0.1", port: UInt16) {
        let endpointPort = NWEndpoint.Port(rawValue: port)!
        connection = NWConnection(host: .init(host), port: endpointPort, using: .tcp)
    }

    public func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.connection.stateUpdateHandler = nil
                    cont.resume()
                case let .failed(error):
                    self?.connection.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Receive up to `max` bytes (returns fewer if that is what arrived).
    public func receive(max: Int = 65536) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if let data, !data.isEmpty { cont.resume(returning: [UInt8](data)); return }
                if isComplete { cont.resume(returning: []); return }
                cont.resume(returning: [])
            }
        }
    }

    /// Receive exactly `count` bytes (loops until satisfied or the peer closes).
    public func receiveExactly(_ count: Int) async throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        while out.count < count {
            let chunk = try await receive(max: count - out.count)
            if chunk.isEmpty { break } // peer closed
            out.append(contentsOf: chunk)
        }
        return out
    }

    public func send(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    public func cancel() { connection.cancel() }
}
