# SwiftData + CloudKit & iCloud Storage

## SwiftData + CloudKit Integration

### Basic Setup

```swift
import SwiftData

@Model
class Note {
    var title: String
    var content: String
    var createdAt: Date

    init(title: String, content: String) {
        self.title = title
        self.content = content
        self.createdAt = Date()
    }
}

// Enable CloudKit sync with one line
let container = try ModelContainer(
    for: Note.self,
    configurations: ModelConfiguration(
        cloudKitDatabase: .private("iCloud.com.example.app")
    )
)
```

That is the entire integration. SwiftData handles sync, change tracking, and conflict resolution automatically.

### Schema Compatibility Constraints

SwiftData+CloudKit imposes restrictions that plain SwiftData does not:

| Constraint | Reason |
|---|---|
| No `@Attribute(.unique)` | CloudKit has no unique constraint support |
| All properties must have defaults or be optional | New fields must be backward-compatible across devices running older app versions |
| No required relationships | CloudKit cannot enforce relationship presence |
| No ordered relationships | CloudKit does not guarantee relationship ordering |
| No deny delete rules | CloudKit cannot cascade-enforce deletes across records |

```swift
// Works with CloudKit
@Model
class Task {
    var title: String = ""         // default value
    var notes: String?             // optional
    var dueDate: Date?             // optional
    var tags: [String] = []        // default empty array
    var project: Project?          // optional relationship

    init(title: String) {
        self.title = title
    }
}

// Breaks with CloudKit
@Model
class BrokenTask {
    @Attribute(.unique) var id: UUID  // unique not supported
    var title: String                 // no default, not optional
    @Relationship(deleteRule: .deny)
    var subtasks: [Subtask]           // deny delete rule not supported
}
```

### Conflict Resolution

SwiftData+CloudKit uses last-writer-wins at the field level. If device A changes `title` and device B changes `notes` on the same record, both changes merge. If both change `title`, the last write to reach the server wins.

There is no custom conflict resolution hook. If you need merge logic, use CKSyncEngine instead.

### Multiple Configurations

```swift
// Sync some models, keep others local-only
let cloudConfig = ModelConfiguration(
    "cloud",
    schema: Schema([Note.self, Tag.self]),
    cloudKitDatabase: .private("iCloud.com.example.app")
)

let localConfig = ModelConfiguration(
    "local",
    schema: Schema([CacheEntry.self, DebugLog.self]),
    cloudKitDatabase: .none
)

let container = try ModelContainer(
    for: Note.self, Tag.self, CacheEntry.self, DebugLog.self,
    configurations: cloudConfig, localConfig
)
```

### Monitoring Sync Status

SwiftData does not expose sync status directly. To observe sync events, use the underlying NSPersistentCloudKitContainer notifications:

```swift
NotificationCenter.default.addObserver(
    forName: NSPersistentCloudKitContainer.eventChangedNotification,
    object: nil,
    queue: .main
) { notification in
    guard let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event else { return }

    if event.endDate != nil {
        // Event completed
        if let error = event.error {
            handleSyncError(error)
        }
    }
}
```

## NSPersistentCloudKitContainer (Core Data)

For apps using Core Data instead of SwiftData:

```swift
import CoreData

let container = NSPersistentCloudKitContainer(name: "MyApp")

// Configure for CloudKit
guard let description = container.persistentStoreDescriptions.first else { return }
description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
    containerIdentifier: "iCloud.com.example.app"
)

// Optional: enable history tracking (required for CloudKit sync)
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

container.loadPersistentStores { description, error in
    if let error { fatalError("Store failed: \(error)") }
}

// Listen for remote changes
NotificationCenter.default.addObserver(
    forName: .NSPersistentStoreRemoteChange,
    object: container.persistentStoreCoordinator,
    queue: .main
) { _ in
    refreshUI()
}
```

### Schema Initialization for CloudKit

```swift
// Initialize CloudKit schema from Core Data model (development only)
// Run this once to push your schema to CloudKit servers
#if DEBUG
do {
    try container.initializeCloudKitSchema(options: [])
} catch {
    print("CloudKit schema init failed: \(error)")
}
#endif
```

## iCloud Drive Document Storage

### UIDocument for Document-Based Apps

```swift
class TextDocument: UIDocument {
    var text: String = ""

    override func contents(forType typeName: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
}
```

### Saving to iCloud Drive

```swift
func saveDocument(_ text: String, filename: String) throws {
    guard let containerURL = FileManager.default.url(
        forUbiquityContainerIdentifier: nil
    ) else {
        throw CloudError.iCloudNotAvailable
    }

    let documentsURL = containerURL.appendingPathComponent("Documents")
    try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)

    let fileURL = documentsURL.appendingPathComponent(filename)
    let document = TextDocument(fileURL: fileURL)
    document.text = text
    document.save(to: fileURL, for: .forCreating)
}
```

### File Coordination

Always use NSFileCoordinator when reading or writing iCloud Drive files to prevent data corruption from concurrent sync operations.

```swift
// Coordinated read
func readFile(at url: URL) throws -> Data {
    let coordinator = NSFileCoordinator()
    var readError: NSError?
    var result: Data?

    coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordURL in
        result = try? Data(contentsOf: coordURL)
    }

    if let error = readError { throw error }
    guard let data = result else { throw CloudError.readFailed }
    return data
}

// Coordinated write
func writeFile(_ data: Data, to url: URL) throws {
    let coordinator = NSFileCoordinator()
    var writeError: NSError?

    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &writeError) { coordURL in
        try? data.write(to: coordURL)
    }

    if let error = writeError { throw error }
}
```

### Monitoring iCloud Drive Files

```swift
class ICloudFileMonitor {
    private let query = NSMetadataQuery()

    func startMonitoring() {
        query.predicate = NSPredicate(format: "%K LIKE '*.txt'", NSMetadataItemFSNameKey)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query, queue: .main
        ) { [weak self] _ in
            self?.processResults()
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query, queue: .main
        ) { [weak self] _ in
            self?.processResults()
        }

        query.start()
    }

    private func processResults() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        for item in query.results {
            guard let metadata = item as? NSMetadataItem,
                  let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                continue
            }
            let downloadStatus = metadata.value(
                forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
            ) as? String
            // .current = downloaded, .notDownloaded = cloud-only
        }
    }
}
```

### Triggering Downloads

```swift
// iCloud Drive files may be cloud-only (not on device)
func ensureDownloaded(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])

    if values.ubiquitousItemDownloadingStatus != .current {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        // Monitor NSMetadataQuery for download completion
    }
}
```

### iCloud Drive Conflict Resolution

```swift
func resolveConflicts(at url: URL) throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else { return }

    // Strategy: keep current version, discard conflicts
    for conflict in conflicts {
        conflict.isResolved = true
    }
    try NSFileVersion.removeOtherVersionsOfItem(at: url)
}

// Or let user choose
func presentConflictChoice(at url: URL) throws -> NSFileVersion {
    let current = try NSFileVersion.currentVersionOfItem(at: url)
    let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []

    // Present all versions to user with metadata
    for version in [current] + conflicts {
        print("Modified: \(version.modificationDate ?? Date())")
        print("Device: \(version.localizedNameOfSavingComputer ?? "Unknown")")
    }

    // After user chooses, replace and clean up
    let chosen = conflicts[0]  // user's choice
    try chosen.replaceItem(at: url, options: [])
    chosen.isResolved = true
    for conflict in conflicts where conflict != chosen {
        conflict.isResolved = true
    }
    try NSFileVersion.removeOtherVersionsOfItem(at: url)
    return chosen
}
```

## NSUbiquitousKeyValueStore

For syncing small preferences across devices. Not for app data.

### Limits

- Total storage: 1 MB
- Maximum keys: 1024
- Maximum value size per key: 1 MB

### Usage

```swift
let store = NSUbiquitousKeyValueStore.default

// Write
store.set(true, forKey: "darkModeEnabled")
store.set(14.0, forKey: "fontSize")
store.set(["home", "work"], forKey: "savedLocations")
store.synchronize()  // hint to sync, not a guarantee

// Read
let darkMode = store.bool(forKey: "darkModeEnabled")
let fontSize = store.double(forKey: "fontSize")
let locations = store.array(forKey: "savedLocations") as? [String] ?? []
```

### Observing External Changes

```swift
NotificationCenter.default.addObserver(
    forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
    object: NSUbiquitousKeyValueStore.default,
    queue: .main
) { notification in
    guard let userInfo = notification.userInfo,
          let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }

    switch reason {
    case NSUbiquitousKeyValueStoreServerChange:
        // Another device changed a value
        let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        applyRemoteChanges(changedKeys)

    case NSUbiquitousKeyValueStoreInitialSyncChange:
        // First sync after install — merge with local defaults
        mergeWithLocalDefaults()

    case NSUbiquitousKeyValueStoreQuotaViolationChange:
        // Over the 1 MB limit — remove non-essential keys
        pruneStore()

    default:
        break
    }
}
```

## Testing CloudKit Locally

### In-Memory Container for Unit Tests

```swift
// SwiftData — test without CloudKit by omitting cloudKitDatabase
@Test func noteCreation() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Note.self, configurations: config)
    let context = ModelContext(container)

    let note = Note(title: "Test", content: "Body")
    context.insert(note)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Note>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.title == "Test")
}
```

### Testing CKSyncEngine Delegate Logic

Isolate your delegate logic from the actual sync engine:

```swift
protocol SyncStore {
    func applyRemoteChange(_ record: CKRecord) async
    func deleteRecord(_ id: CKRecord.ID) async
    func pendingChanges() async -> [CKRecord]
}

// Test with a mock store
class MockSyncStore: SyncStore {
    var applied: [CKRecord] = []
    var deleted: [CKRecord.ID] = []

    func applyRemoteChange(_ record: CKRecord) async {
        applied.append(record)
    }

    func deleteRecord(_ id: CKRecord.ID) async {
        deleted.append(id)
    }

    func pendingChanges() async -> [CKRecord] { [] }
}
```

### CloudKit Environment for Integration Tests

CloudKit operations in tests require a real iCloud account. For CI, use a dedicated test container:

```swift
// Use a separate container for tests to avoid polluting production data
let testContainer = CKContainer(identifier: "iCloud.com.example.app.test")
```

### Checking Account Availability in Tests

```swift
func skipIfNoiCloud() async throws {
    let status = try await CKContainer.default().accountStatus()
    guard status == .available else {
        // Skip test — no iCloud account on this machine/simulator
        return
    }
}
```

### Simulator Limitations

- Simulators support CloudKit sync but require an iCloud account signed in on the Mac
- Sync timing is less predictable on simulators
- Test on real devices for production-critical sync flows
- Two simulators on the same Mac share the same iCloud account, which is useful for multi-device testing
