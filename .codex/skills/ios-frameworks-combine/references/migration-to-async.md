# Migration from Combine to async/await

## Operator-to-AsyncAlgorithms Mapping

`import AsyncAlgorithms` for the async equivalents.

| Combine | AsyncAlgorithms / stdlib | Notes |
|---------|-------------------------|-------|
| `map` | `.map` | stdlib AsyncSequence |
| `compactMap` | `.compactMap` | stdlib AsyncSequence |
| `filter` | `.filter` | stdlib AsyncSequence |
| `flatMap` | `.flatMap` | stdlib AsyncSequence |
| `first(where:)` | `.first(where:)` | stdlib AsyncSequence |
| `prefix(_:)` | `.prefix(_:)` | stdlib AsyncSequence |
| `dropFirst(_:)` | `.dropFirst(_:)` | stdlib AsyncSequence |
| `debounce(for:)` | `.debounce(for:)` | AsyncAlgorithms |
| `throttle(for:latest:)` | `.throttle(for:latest:)` | AsyncAlgorithms |
| `merge(with:)` | `merge(_:_:)` | AsyncAlgorithms, free function |
| `combineLatest(_:)` | `combineLatest(_:_:)` | AsyncAlgorithms, free function |
| `zip(_:)` | `zip(_:_:)` | AsyncAlgorithms, free function |
| `removeDuplicates()` | `.removeDuplicates()` | AsyncAlgorithms |
| `prepend(_:)` | `chain(_:_:)` | AsyncAlgorithms, free function |
| `collect(.byCount(n))` | `.chunks(ofCount:)` | AsyncAlgorithms |
| `collect(.byTime(...))` | `.chunked(by: .repeating(every:))` | AsyncAlgorithms |
| `buffer(size:)` | `.buffer(policy:)` | AsyncAlgorithms |
| `sink { }` | `for await value in stream { }` | Direct replacement |
| `.values` | Already `AsyncSequence` | Use directly |

No AsyncAlgorithms equivalent for `switchToLatest`, `share()`, `multicast`, `catch`, `retry`, or `assign`. These require manual implementation or indicate Combine is still the better fit.

## Publisher.values: Bridging to AsyncSequence

Any Combine publisher exposes `.values` as an `AsyncSequence`:

```swift
// Before: Combine sink
notificationPublisher
    .sink { [weak self] notification in
        self?.handle(notification)
    }
    .store(in: &cancellables)

// After: async for-await
Task {
    for await notification in notificationPublisher.values {
        handle(notification)
    }
}
```

Caveats:
- Loop runs until the publisher completes or the Task is cancelled
- Errors thrown by the publisher terminate the loop
- Single consumer only -- two `for await` loops on the same `.values` is undefined behavior

## Replacing sink with for-await

### Simple value consumption

```swift
// Before
dataPublisher
    .receive(on: RunLoop.main)
    .sink { [weak self] data in
        self?.items = data
    }
    .store(in: &cancellables)

// After
Task { @MainActor in
    for await data in dataPublisher.values {
        items = data
    }
}
```

### With operators

```swift
// Before
$searchText
    .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
    .removeDuplicates()
    .sink { [weak self] query in
        self?.performSearch(query)
    }
    .store(in: &cancellables)

// After (AsyncAlgorithms)
Task { @MainActor in
    for await query in searchTerms.debounce(for: .milliseconds(300)).removeDuplicates() {
        performSearch(query)
    }
}
```

Where `searchTerms` is an `AsyncStream<String>` fed by the text field.

## Replacing @Published with @Observable

```swift
// Before: ObservableObject + @Published
class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: Error?
    private var cancellables = Set<AnyCancellable>()

    func load() {
        isLoading = true
        api.fetchItems()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let err) = completion {
                        self?.error = err
                    }
                },
                receiveValue: { [weak self] items in
                    self?.items = items
                }
            )
            .store(in: &cancellables)
    }
}

// After: @Observable + async/await
@Observable
@MainActor
final class ViewModel {
    var items: [Item] = []
    var isLoading = false
    var error: Error?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await api.fetchItems()
        } catch {
            self.error = error
        }
    }
}
```

What you eliminate:
- `ObservableObject` conformance
- `@Published` property wrappers
- `Set<AnyCancellable>` storage
- `[weak self]` in every closure
- `receive(on: RunLoop.main)` scheduling
- Completion handling boilerplate

## Replacing PassthroughSubject with AsyncStream

```swift
// Before: PassthroughSubject
class EventBus {
    let events = PassthroughSubject<Event, Never>()

    func emit(_ event: Event) {
        events.send(event)
    }
}

// Consumer
eventBus.events
    .sink { [weak self] event in self?.handle(event) }
    .store(in: &cancellables)

// After: AsyncStream
class EventBus {
    private let continuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.continuation = continuation
    }

    func emit(_ event: Event) {
        continuation.yield(event)
    }
}

// Consumer
Task {
    for await event in eventBus.events {
        handle(event)
    }
}
```

Key difference: `AsyncStream` is single-consumer. If you need multiple consumers, keep `PassthroughSubject` or create multiple streams.

## Replacing CurrentValueSubject with AsyncStream + Initial Value

```swift
// Before
let status = CurrentValueSubject<ConnectionStatus, Never>(.disconnected)
// Subscriber immediately gets .disconnected, then future updates

// After
actor ConnectionMonitor {
    private(set) var status: ConnectionStatus = .disconnected
    private var continuation: AsyncStream<ConnectionStatus>.Continuation?

    var statusUpdates: AsyncStream<ConnectionStatus> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(status)  // Emit current value immediately
        }
    }

    func update(_ newStatus: ConnectionStatus) {
        status = newStatus
        continuation?.yield(newStatus)
    }
}
```

## Common Migration Patterns

### NotificationCenter

```swift
// Before
NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
    .sink { [weak self] _ in self?.refresh() }
    .store(in: &cancellables)

// After
Task { [weak self] in
    for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
        await self?.refresh()
    }
}
```

### KVO Observation

```swift
// Before
scrollView.publisher(for: \.contentOffset)
    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
    .sink { [weak self] offset in self?.updateHeader(offset) }
    .store(in: &cancellables)

// After (with AsyncAlgorithms)
Task { @MainActor in
    let offsets = scrollView.publisher(for: \.contentOffset).values
    for await offset in offsets.throttle(for: .milliseconds(100), latest: true) {
        updateHeader(offset)
    }
}
```

Note: KVO still uses Combine's `publisher(for:)` to create the source, then `.values` bridges to async. There is no native async KVO API.

### Debounced Search

```swift
// Before
$searchText
    .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
    .removeDuplicates()
    .flatMap { query in
        api.search(query).replaceError(with: [])
    }
    .receive(on: RunLoop.main)
    .assign(to: &$results)

// After
@Observable
@MainActor
final class SearchViewModel {
    var searchText = ""
    private(set) var results: [Result] = []
    private var continuation: AsyncStream<String>.Continuation?

    private lazy var queries: AsyncStream<String> = {
        AsyncStream { self.continuation = $0 }
    }()

    func textChanged(_ text: String) {
        searchText = text
        continuation?.yield(text)
    }

    func startSearching() {
        Task {
            for await query in queries.debounce(for: .milliseconds(300)).removeDuplicates() {
                do {
                    results = try await api.search(query)
                } catch {
                    results = []
                }
            }
        }
    }
}
```

## When Combine Is Still the Right Choice

Do not migrate these patterns -- Combine handles them better or has no async equivalent:

**Multi-subscriber broadcasting** -- `PassthroughSubject` and `CurrentValueSubject` support multiple subscribers natively. `AsyncStream` is single-consumer.

**Complex operator chains with switchToLatest** -- No async equivalent. If you need automatic cancellation of the previous inner publisher when a new outer value arrives, Combine's `map` + `switchToLatest` is the right tool.

**share() / multicast** -- Sharing a single execution across multiple consumers has no async equivalent. If multiple parts of the app need the same publisher's output without duplicating work, keep Combine.

**Existing working pipelines** -- If a pipeline works, don't rewrite it. Bridge with `.values` at the boundary where async code needs the data.

**UIKit KVO bridges** -- `publisher(for:)` is the only reactive KVO API. Use `.values` to bridge into async when needed, but the source remains Combine.

## Migration Strategy

```
1. New code       --> async/await + @Observable
2. Boundaries     --> .values (Combine to async), Future (async to Combine)
3. Existing code  --> leave working pipelines alone
4. Rewrite        --> only when the pipeline needs significant changes anyway
```

Do not migrate all Combine code at once. Incremental bridging is safer and cheaper than a rewrite.
