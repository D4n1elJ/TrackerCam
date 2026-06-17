# Network.framework Patterns

## iOS 26+ NetworkConnection (Async/Await)

### TCP with TLS

```swift
import Network

func connectTLS(host: String, port: UInt16) async throws {
    let connection = NetworkConnection(
        to: .hostPort(host: .init(host), port: .init(rawValue: port)!),
        using: .tls
    )

    try await connection.open()

    // Send
    let message = "Hello".data(using: .utf8)!
    try await connection.send(message)

    // Receive
    let data = try await connection.receive(minimumLength: 1, maximumLength: 65536)
    print("Received \(data.count) bytes")

    connection.close()
}
```

### UDP

```swift
func sendUDP(host: String, port: UInt16, payload: Data) async throws {
    let connection = NetworkConnection(
        to: .hostPort(host: .init(host), port: .init(rawValue: port)!),
        using: .udp
    )

    try await connection.open()
    try await connection.send(payload)
    connection.close()
}
```

### TLV Framing

Custom message framing with type-length-value:

```swift
struct MessageFramer: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: MessageFramer.self)
    static var label: String { "MessageFramer" }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        // Parse header to determine message length
        // Return minimum bytes needed for next parse
    }

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        // Write header + payload
    }
}
```

## iOS 12-25 NWConnection (Callbacks)

### Connection Lifecycle

```swift
final class TCPClient {
    private var connection: NWConnection?

    func connect(host: String, port: UInt16) {
        let connection = NWConnection(
            host: .init(host),
            port: .init(rawValue: port)!,
            using: .tcp
        )

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .setup:
                break
            case .preparing:
                break
            case .ready:
                self?.onConnected()
            case .waiting(let error):
                // Network constrained — NOT connected
                self?.onWaiting(error)
            case .failed(let error):
                self?.onFailed(error)
            case .cancelled:
                break
            @unknown default:
                break
            }
        }

        connection.start(queue: .global())
        self.connection = connection
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    deinit {
        connection?.cancel()
    }
}
```

### Send and Receive

```swift
extension TCPClient {
    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onSendError(error)
            }
        })
    }

    func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                self?.onReceived(data)
            }
            if isComplete {
                self?.onDisconnected()
            } else if let error {
                self?.onReceiveError(error)
            } else {
                self?.receiveLoop()  // schedule next receive
            }
        }
    }
}
```

### Bridging to async/await

```swift
extension NWConnection {
    func sendAsync(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receiveAsync(min: Int = 1, max: Int = 65536) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: min, maximumLength: max) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NWError.posix(.ECONNRESET))
                }
            }
        }
    }
}
```

## Network Path Monitoring

### Reacting to Network Changes (Not Pre-Checking)

```swift
final class NetworkMonitor {
    private let monitor = NWPathMonitor()

    var isConnected: Bool { monitor.currentPath.status == .satisfied }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.onNetworkAvailable()
            } else {
                self?.onNetworkUnavailable()
            }
        }
        monitor.start(queue: .global())
    }

    func stop() {
        monitor.cancel()
    }
}
```

**Use for:** updating UI state (show/hide offline banner), triggering sync when back online.

**Do NOT use for:** gating requests (just attempt the request and handle errors).

## Listeners and Discovery

### NWListener (Server)

```swift
let listener = try NWListener(using: .tcp, on: 8080)
listener.newConnectionHandler = { [weak self] connection in
    self?.handleNewConnection(connection)
}
listener.start(queue: .global())
```

### NWBrowser (Bonjour Discovery)

```swift
let browser = NWBrowser(for: .bonjour(type: "_myapp._tcp", domain: nil), using: .tcp)
browser.browseResultsChangedHandler = { results, changes in
    for result in results {
        // result.endpoint contains the discovered service
    }
}
browser.start(queue: .global())
```
