# Networking

Review and write iOS networking code for correctness, modern API usage, and production reliability.

## Responsibility

**Owns:** URLSession HTTP requests, Network.framework connections (NWConnection, NetworkConnection), structured concurrency networking, connection configuration, TLS, error handling, network transitions, reachability patterns, connection diagnostics.

**Does NOT own:** Server-side API design, backend architecture, GraphQL schema, authentication token management (see ios-architecture), UI loading states (see swiftui-patterns).

## Core Principles

1. **URLSession for HTTP.** Don't use Network.framework for standard REST/GraphQL. URLSession handles HTTP semantics, caching, cookies, redirects, and background transfers.
2. **Network.framework for custom protocols.** TCP/UDP streams, WebSockets, custom framing, peer-to-peer discovery, and low-level connection management.
3. **iOS 26+ NetworkConnection for new code.** Async/await native, replaces NWConnection callback patterns. Use NWConnection only for iOS 12-25 back-compat.
4. **Never pre-check reachability.** `SCNetworkReachability` races with reality. Just attempt the connection and handle errors. The network can change between check and use.
5. **Handle the waiting state.** NWConnection/NetworkConnection can sit in `.waiting` indefinitely on constrained networks. Don't treat it as connected.
6. **Resume continuations exactly once.** When bridging NWConnection callbacks to async/await, every code path must resume the continuation.
7. **Test on real devices.** Simulator networking differs from device behaviour (cellular, VPN, proxy, IPv6-only).

## Decision Tree

### Which API?

```
Is this HTTP/HTTPS?
├── Yes → URLSession
│   ├── Simple request/response → URLSession.data(for:)
│   ├── Upload with progress → URLSession.upload(for:from:)
│   ├── Download to file → URLSession.download(for:)
│   ├── Background transfer → Background URLSession configuration
│   └── Server-sent events → URLSession.bytes(for:)
│
└── No → Network.framework
    ├── iOS 26+ available?
    │   ├── Yes → NetworkConnection (async/await native)
    │   └── No → NWConnection (callback-based)
    ├── TCP stream → NWConnection / NetworkConnection with .tcp
    ├── UDP → NWConnection / NetworkConnection with .udp
    ├── WebSocket → URLSessionWebSocketTask or NWConnection with .webSocket
    ├── TLS custom → NWProtocolTLS.Options
    ├── Bonjour/discovery → NWBrowser / NetworkBrowser
    └── Listening → NWListener / NetworkListener
```

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `SCNetworkReachability` pre-check | Races with reality — network can change between check and connect | Just connect and handle errors |
| Blocking socket on main thread | ANR / watchdog kill | Use async APIs or dispatch to background |
| `getaddrinfo()` / manual DNS | Bypasses system DNS cache, Happy Eyeballs, VPN config | Use URLSession or NWConnection (handles DNS automatically) |
| Hardcoded IP addresses | Breaks IPv6-only networks (carrier requirement) | Always use hostnames |
| Ignoring `.waiting` state | App appears connected but no data flows | Show "connecting" UI, implement timeout |
| Missing `[weak self]` in NWConnection handlers | Retain cycle — connection and handler reference each other | Capture `[weak self]` in all state/receive handlers |
| Mixing async/completion styles | Confusing control flow, easy to miss error paths | Pick one style per layer |
| No cancellation on view disappear | Zombie connections wasting battery | Cancel in `.task` or `deinit` |
| URLSession never invalidated | Delegate and connections leak until process exit | Call `finishTasksAndInvalidate()` for non-shared sessions |

## URLSession Patterns

### Simple GET with async/await

```swift
func fetchUser(id: String) async throws -> User {
    let url = URL(string: "https://api.example.com/users/\(id)")!
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw NetworkError.badResponse
    }

    return try JSONDecoder().decode(User.self, from: data)
}
```

### POST with Codable Body

```swift
func createUser(_ user: NewUser) async throws -> User {
    var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(user)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw NetworkError.badResponse
    }

    return try JSONDecoder().decode(User.self, from: data)
}
```

### Retry with Exponential Backoff

```swift
func fetchWithRetry<T: Decodable>(
    request: URLRequest,
    maxAttempts: Int = 3,
    as type: T.Type
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<maxAttempts {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NetworkError.badResponse
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            lastError = error
            if attempt < maxAttempts - 1 {
                let delay = Double(1 << attempt)  // 1s, 2s, 4s
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    throw lastError ?? NetworkError.unknown
}
```

### Cancellation in SwiftUI

```swift
struct UserView: View {
    let userID: String
    @State private var user: User?

    var body: some View {
        content
            .task(id: userID) {
                // Automatically cancelled when view disappears or userID changes
                user = try? await fetchUser(id: userID)
            }
    }
}
```

## Network.framework Patterns

### iOS 26+ NetworkConnection (Async/Await)

```swift
import Network

func connect(to host: String, port: UInt16) async throws {
    let connection = NetworkConnection(
        to: .hostPort(host: .init(host), port: .init(rawValue: port)!),
        using: .tcp
    )

    try await connection.open()

    // Send
    try await connection.send(data)

    // Receive
    let received = try await connection.receive(minimumLength: 1, maximumLength: 65536)

    // Close
    connection.close()
}
```

### iOS 12-25 NWConnection (Callbacks)

```swift
let connection = NWConnection(
    host: .init(host),
    port: .init(rawValue: port)!,
    using: .tcp
)

connection.stateUpdateHandler = { [weak self] state in
    switch state {
    case .ready:
        self?.connectionReady()
    case .waiting(let error):
        self?.connectionWaiting(error)  // don't ignore this
    case .failed(let error):
        self?.connectionFailed(error)
    default:
        break
    }
}

connection.start(queue: .global())
```

### TLS Configuration

```swift
let tlsOptions = NWProtocolTLS.Options()
let parameters = NWParameters(tls: tlsOptions, tcp: .init())

// Certificate pinning
sec_protocol_options_set_verify_block(
    tlsOptions.securityProtocolOptions,
    { metadata, trust, complete in
        // Validate server certificate against pinned cert
        let isValid = validateCertificate(trust)
        complete(isValid)
    },
    .global()
)
```

## Connection Diagnostics

### Symptom → Diagnosis

| Symptom | Likely Cause | Check |
|---|---|---|
| Connection timeout | DNS failure, firewall, wrong port | Check `nslookup`, verify port, test on different network |
| TLS handshake failure | Certificate expired, pinning mismatch, ATS violation | Check cert validity, review pinning config, check Info.plist ATS exceptions |
| Works on Wi-Fi, fails on cellular | IPv6-only network, hardcoded IPv4 | Remove hardcoded IPs, test on IPv6-only hotspot |
| Works in simulator, fails on device | Proxy/VPN, ATS, missing entitlements | Test on device over cellular, check entitlements |
| Connection stuck in `.waiting` | Constrained network, no route | Implement timeout, show "connecting" state |
| Intermittent failures | Network transition (Wi-Fi ↔ cellular) | Handle NWPath changes, retry on better path |
| Data corruption | Missing content-length, chunked encoding | Log raw response bytes, check `Transfer-Encoding` |

### Enabling Network Logging

```swift
// In scheme environment variables:
// CFNETWORK_DIAGNOSTICS = 3  (verbose)
// OS_ACTIVITY_MODE = debug

// Or in code:
import os
let logger = Logger(subsystem: "com.app.networking", category: "connection")
```

## URLSession Lifecycle

`URLSession` retains its delegate strongly. Non-shared sessions that are never invalidated leak the delegate (and all its references) for the lifetime of the process.

```swift
// WRONG: Session retains delegate forever.
class NetworkService {
    let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    // delegate (self) is never released — retain cycle
}

// RIGHT: Invalidate when done.
class NetworkService {
    private lazy var session = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil
    )

    func teardown() {
        session.finishTasksAndInvalidate()  // breaks the retain cycle
    }
}
```

**Rules:**
- `URLSession.shared` — never invalidate (singleton, no delegate)
- Custom sessions with a delegate — call `finishTasksAndInvalidate()` when the owning object tears down
- Custom sessions without a delegate — still call `finishTasksAndInvalidate()` to release internal resources
- Creating sessions in a loop without invalidating — each one leaks connections and memory

## Pre-Ship Checklist

- [ ] No `SCNetworkReachability` pre-checks — just connect and handle errors
- [ ] No hardcoded IP addresses — hostnames only
- [ ] All NWConnection handlers capture `[weak self]`
- [ ] `.waiting` state handled (timeout or UI indicator)
- [ ] Connections cancelled on view disappear / task cancellation
- [ ] Tested on real device over cellular
- [ ] Tested on IPv6-only network (Settings → Developer → Network Link Conditioner)
- [ ] Error responses decoded and surfaced to user
- [ ] Retry logic has exponential backoff and max attempts
- [ ] No sensitive data logged (tokens, passwords, PII)
- [ ] ATS exceptions in Info.plist are documented and minimised
- [ ] Custom URLSessions are invalidated on teardown (`finishTasksAndInvalidate()`)

## References

- `references/urlsession-patterns.md` — Request configuration, authentication, background transfers, download/upload, caching
- `references/network-framework-patterns.md` — NWConnection lifecycle, NetworkConnection (iOS 26+), framing, discovery, listeners
- `references/connection-diagnostics.md` — Systematic debugging for connection failures, TLS issues, network transitions
