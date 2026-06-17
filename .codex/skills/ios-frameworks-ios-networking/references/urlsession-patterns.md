# URLSession Patterns

## Configuration

### Shared vs Custom Sessions

```swift
// Shared — fine for simple requests, no customisation
let (data, response) = try await URLSession.shared.data(from: url)

// Custom — when you need timeouts, caching, auth, or background
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30
config.timeoutIntervalForResource = 300
config.waitsForConnectivity = true  // wait instead of failing immediately
config.httpAdditionalHeaders = ["Authorization": "Bearer \(token)"]

let session = URLSession(configuration: config)
```

### Background Transfers

```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.app.upload")
config.isDiscretionary = false           // start immediately
config.sessionSendsLaunchEvents = true   // wake app on completion

let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

// Upload
let task = session.uploadTask(with: request, fromFile: fileURL)
task.resume()

// Handle in AppDelegate
func application(_ application: UIApplication,
                 handleEventsForBackgroundURLSession identifier: String,
                 completionHandler: @escaping () -> Void) {
    backgroundCompletionHandler = completionHandler
}
```

## Request Patterns

### Authenticated Requests

```swift
struct APIClient {
    let session: URLSession
    let baseURL: URL
    let tokenProvider: () async throws -> String

    func request<T: Decodable>(_ endpoint: String, method: String = "GET") async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw NetworkError.unauthorized
        case 429:
            throw NetworkError.rateLimited
        default:
            throw NetworkError.httpError(statusCode: http.statusCode)
        }
    }
}
```

### Streaming with AsyncBytes

```swift
// Server-sent events or line-delimited JSON
func streamEvents(from url: URL) async throws -> AsyncThrowingStream<Event, Error> {
    let (bytes, response) = try await URLSession.shared.bytes(from: url)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NetworkError.badResponse
    }

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    if let event = Event(from: line) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

### Download with Progress

```swift
func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
    let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

    guard let http = response as? HTTPURLResponse,
          let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
          let totalBytes = Int(contentLength) else {
        throw NetworkError.badResponse
    }

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let output = OutputStream(url: tempURL, append: false)!
    output.open()
    defer { output.close() }

    var receivedBytes = 0
    for try await byte in asyncBytes {
        var b = byte
        output.write(&b, maxLength: 1)
        receivedBytes += 1
        progress(Double(receivedBytes) / Double(totalBytes))
    }

    return tempURL
}
```

## Caching

### URL Cache Configuration

```swift
let config = URLSessionConfiguration.default
config.urlCache = URLCache(
    memoryCapacity: 10 * 1024 * 1024,   // 10 MB memory
    diskCapacity: 100 * 1024 * 1024      // 100 MB disk
)
config.requestCachePolicy = .returnCacheDataElseLoad
```

### Cache-Control Headers

| Policy | Behaviour |
|--------|-----------|
| `.useProtocolCachePolicy` | Respect server's Cache-Control headers (default) |
| `.returnCacheDataElseLoad` | Use cache if available, fetch if not |
| `.returnCacheDataDontLoad` | Offline mode — only cache, no network |
| `.reloadIgnoringLocalCacheData` | Always fetch from network |

## Error Handling

### Typed Network Errors

```swift
enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case unauthorized
    case rateLimited
    case noConnection
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .httpError(let code): "Server error (\(code))"
        case .unauthorized: "Session expired — please sign in again"
        case .rateLimited: "Too many requests — try again shortly"
        case .noConnection: "No internet connection"
        case .timeout: "Request timed out"
        }
    }
}
```

### URLError Mapping

```swift
func mapURLError(_ error: URLError) -> NetworkError {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost:
        return .noConnection
    case .timedOut:
        return .timeout
    default:
        return .invalidResponse
    }
}
```
