# CloudKit Patterns

## CKContainer and Database Types

```swift
import CloudKit

// Default container (matches primary container in entitlements)
let container = CKContainer.default()

// Named container
let container = CKContainer(identifier: "iCloud.com.example.app")

// Three database scopes
let privateDB = container.privateCloudDatabase   // User's own data
let publicDB  = container.publicCloudDatabase    // All users
let sharedDB  = container.sharedCloudDatabase    // CKShare collaboration
```

| Scope | Reads | Writes | Quota | SwiftData Support |
|---|---|---|---|---|
| Private | Authenticated user only | Authenticated user only | User's iCloud quota | Yes |
| Public | Anyone (no auth needed) | Authenticated user only | App's CloudKit quota | No |
| Shared | Invited participants | Based on CKShare permission | Owner's iCloud quota | No |

## CKRecord CRUD

### Create

```swift
let record = CKRecord(recordType: "Task")
record["title"] = "Buy groceries" as CKRecordValue
record["isCompleted"] = false as CKRecordValue
record["dueDate"] = Date() as CKRecordValue
record["priority"] = 3 as CKRecordValue

try await privateDB.save(record)
```

### Read

```swift
// By ID
let recordID = CKRecord.ID(recordName: "task-123")
let record = try await privateDB.record(for: recordID)
let title = record["title"] as? String

// By query
let predicate = NSPredicate(format: "isCompleted == NO AND priority > %d", 2)
let query = CKQuery(recordType: "Task", predicate: predicate)
query.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true)]

let (matchResults, queryCursor) = try await privateDB.records(matching: query)

for (recordID, result) in matchResults {
    if case .success(let record) = result {
        print(record["title"] as? String ?? "")
    }
}

// Paginated query
if let cursor = queryCursor {
    let (moreResults, _) = try await privateDB.records(continuingMatchFrom: cursor)
}
```

### Update

```swift
// Always fetch first to avoid serverRecordChanged
let record = try await privateDB.record(for: recordID)
record["title"] = "Updated title" as CKRecordValue
record["isCompleted"] = true as CKRecordValue
try await privateDB.save(record)
```

### Delete

```swift
try await privateDB.deleteRecord(withID: recordID)
```

### Batch Operations

```swift
let operation = CKModifyRecordsOperation(
    recordsToSave: [record1, record2],
    recordIDsToDelete: [deletedID]
)
operation.savePolicy = .changedKeys  // only upload modified fields

// Per-record results — do not skip this
operation.perRecordSaveBlock = { recordID, result in
    switch result {
    case .success(let record):
        markSynced(recordID, serverChangeTag: record.recordChangeTag)
    case .failure(let error):
        markFailed(recordID, error: error)
    }
}

operation.perRecordDeleteBlock = { recordID, result in
    if case .failure(let error) = result {
        markDeleteFailed(recordID, error: error)
    }
}

try await privateDB.add(operation)
```

### Silent Data Loss in Batch Operations

Batch operations can lose data without raising errors at the operation level. Watch for these:

| Cause | Symptom | Fix |
|---|---|---|
| Record size > 1 MB | Individual records silently dropped from batch | Split large data into CKAsset |
| Batch partial failure | Some records save, others fail silently | Always check `perRecordSaveBlock` for per-record errors |
| Conflict auto-resolution with `.changedKeys` | Last-writer-wins overwrites valid concurrent edits | Implement merge-based conflict resolution for critical data |
| Asset download not triggered | Record syncs but CKAsset content is missing on the other device | Fetch with `desiredKeys` including the asset field |

## CKAsset (Binary File Storage)

```swift
// CKAsset requires a file URL, not raw Data
let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try imageData.write(to: tempURL)

let record = CKRecord(recordType: "Photo")
record["image"] = CKAsset(fileURL: tempURL)
record["caption"] = "Sunset" as CKRecordValue

try await privateDB.save(record)

// Retrieve
let fetched = try await privateDB.record(for: recordID)
if let asset = fetched["image"] as? CKAsset, let fileURL = asset.fileURL {
    let data = try Data(contentsOf: fileURL)
}
```

## Zones and Custom Zones

The default zone exists in every database. Custom zones unlock:
- Atomic commits (save multiple records as one transaction)
- CKFetchRecordZoneChangesOperation (incremental sync with change tokens)
- CKShare (sharing requires a custom zone)

```swift
// Create custom zone
let zone = CKRecordZone(zoneName: "Tasks")
try await privateDB.save(zone)

// Create record in custom zone
let zoneID = CKRecordZone.ID(zoneName: "Tasks")
let recordID = CKRecord.ID(recordName: "task-1", zoneID: zoneID)
let record = CKRecord(recordType: "Task", recordID: recordID)
record["title"] = "In custom zone" as CKRecordValue
try await privateDB.save(record)
```

### Incremental Sync with Change Tokens

```swift
func fetchChanges(in zoneID: CKRecordZone.ID, since token: CKServerChangeToken?) async throws -> CKServerChangeToken? {
    let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
        previousServerChangeToken: token
    )

    let operation = CKFetchRecordZoneChangesOperation(
        recordZoneIDs: [zoneID],
        configurationsByRecordZoneID: [zoneID: config]
    )

    var newToken: CKServerChangeToken?

    operation.recordWasChangedBlock = { recordID, result in
        if case .success(let record) = result {
            applyToLocalStore(record)
        }
    }

    operation.recordWithIDWasDeletedBlock = { recordID, recordType in
        deleteFromLocalStore(recordID)
    }

    operation.recordZoneFetchResultBlock = { zoneID, result in
        if case .success(let (serverToken, _, _)) = result {
            newToken = serverToken
        }
    }

    try await privateDB.add(operation)
    return newToken
}
```

## CKSyncEngine (iOS 17+)

Replaces manual fetch/push cycles. Handles change tokens, batching, retries, and account changes automatically.

```swift
class SyncManager: CKSyncEngineDelegate {
    let syncEngine: CKSyncEngine

    init() throws {
        let config = CKSyncEngine.Configuration(
            database: CKContainer.default().privateCloudDatabase,
            stateSerialization: loadPersistedState(),
            delegate: self
        )
        syncEngine = try CKSyncEngine(config)
    }

    // Queue a local change for upload
    func recordDidChange(_ recordID: CKRecord.ID) {
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    func recordWasDeleted(_ recordID: CKRecord.ID) {
        syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persistState(update.stateSerialization)

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                applyToLocalStore(modification.record)
            }
            for deletion in changes.deletions {
                deleteFromLocalStore(deletion.recordID)
            }

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords {
                markSynced(saved.recordID)
            }
            for failed in sent.failedRecordSaves {
                handleSaveFailure(failed.record.recordID, error: failed.error)
            }

        case .willFetchChanges, .didFetchChanges,
             .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges
        return CKSyncEngine.RecordZoneChangeBatch(
            pendingSaves: pendingRecordsToSave(from: pendingChanges),
            recordIDsToDelete: pendingRecordIDsToDelete(from: pendingChanges)
        )
    }
}
```

## Subscriptions and Push Notifications

### Database Subscription (any change in database)

```swift
let subscription = CKDatabaseSubscription(subscriptionID: "all-private-changes")
let notificationInfo = CKSubscription.NotificationInfo()
notificationInfo.shouldSendContentAvailable = true  // silent push
subscription.notificationInfo = notificationInfo

try await privateDB.save(subscription)
```

### Query Subscription (records matching a predicate)

```swift
let predicate = NSPredicate(format: "priority > 3")
let subscription = CKQuerySubscription(
    recordType: "Task",
    predicate: predicate,
    subscriptionID: "high-priority-tasks",
    options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
)

let info = CKSubscription.NotificationInfo()
info.alertBody = "High priority task changed"
info.shouldBadge = true
subscription.notificationInfo = info

try await privateDB.save(subscription)
```

### Record Zone Subscription

```swift
let zoneID = CKRecordZone.ID(zoneName: "Tasks")
let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "tasks-zone")

let info = CKSubscription.NotificationInfo()
info.shouldSendContentAvailable = true
subscription.notificationInfo = info

try await privateDB.save(subscription)
```

### Handling Push

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any]
) async -> UIBackgroundFetchResult {
    let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)

    guard notification.subscriptionID == "all-private-changes" else {
        return .noData
    }

    do {
        try await fetchLatestChanges()
        return .newData
    } catch {
        return .failed
    }
}
```

## CKShare and Sharing Workflows

Sharing requires records in a **custom zone** (not the default zone).

### Create a Share

```swift
let record = try await privateDB.record(for: recordID)

let share = CKShare(rootRecord: record)
share[CKShare.SystemFieldKey.title] = "Shared Task List" as CKRecordValue
share.publicPermission = .none  // invite-only

let operation = CKModifyRecordsOperation(
    recordsToSave: [record, share],
    recordIDsToDelete: nil
)
try await privateDB.add(operation)
```

### Present Sharing UI (UIKit)

```swift
let controller = UICloudSharingController(share: share, container: container)
controller.delegate = self
present(controller, animated: true)

extension ViewController: UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController,
                                failedToSaveShareWithError error: Error) {
        handleError(error)
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "My Shared List"
    }
}
```

### Present Sharing UI (SwiftUI)

```swift
// CloudSharingView wrapping UICloudSharingController
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
```

### Accept a Share

```swift
func userDidAcceptCloudKitShareWith(_ metadata: CKShare.Metadata) {
    let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
    operation.acceptSharesResultBlock = { result in
        switch result {
        case .success: refreshSharedData()
        case .failure(let error): handleError(error)
        }
    }
    CKContainer(identifier: metadata.containerIdentifier).add(operation)
}
```

### Manage Participants

```swift
for participant in share.participants {
    let name = participant.userIdentity.nameComponents?.formatted() ?? "Unknown"
    let status = participant.acceptanceStatus   // .pending, .accepted, .removed
    let permission = participant.permission      // .readOnly, .readWrite, .none
}

// Remove a participant
share.removeParticipant(participant)
try await privateDB.save(share)
```

## Error Handling

### Retryable Errors

```swift
func saveWithRetry(_ record: CKRecord, maxAttempts: Int = 3) async throws {
    var lastError: Error?

    for attempt in 0..<maxAttempts {
        do {
            try await privateDB.save(record)
            return
        } catch let error as CKError {
            lastError = error

            if let retryAfter = error.retryAfterSeconds {
                try await Task.sleep(for: .seconds(retryAfter))
                continue
            }

            switch error.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable,
                 .zoneBusy, .requestRateLimited:
                let delay = pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            default:
                throw error  // non-retryable
            }
        }
    }

    throw lastError ?? CKError(.internalError)
}
```

### Conflict Resolution

```swift
func saveResolvingConflicts(_ record: CKRecord) async throws {
    do {
        try await privateDB.save(record)
    } catch let error as CKError where error.code == .serverRecordChanged {
        guard let serverRecord = error.serverRecord,
              let clientRecord = error.clientRecord else {
            throw error
        }

        // Merge strategy: apply client changes onto server version
        let merged = serverRecord
        for key in clientRecord.changedKeys() {
            merged[key] = clientRecord[key]
        }

        try await privateDB.save(merged)
    }
}
```

### Partial Failure Handling

```swift
func handlePartialFailure(_ error: CKError) {
    guard error.code == .partialFailure,
          let partialErrors = error.partialErrorsByItemID else { return }

    for (itemID, itemError) in partialErrors {
        if let ckError = itemError as? CKError {
            switch ckError.code {
            case .serverRecordChanged:
                queueForConflictResolution(itemID)
            case .unknownItem:
                removeFromLocalStore(itemID)
            default:
                queueForRetry(itemID, error: ckError)
            }
        }
    }
}
```

### CKError Quick Reference

| Code | Name | Retryable | Action |
|---|---|---|---|
| 1 | `internalError` | Maybe | Retry once, then report |
| 2 | `partialFailure` | Depends | Check `partialErrorsByItemID` per record |
| 3 | `networkUnavailable` | Yes | Queue for when online |
| 4 | `networkFailure` | Yes | Retry with backoff |
| 6 | `serviceUnavailable` | Yes | Respect `retryAfterSeconds` |
| 11 | `zoneBusy` | Yes | Respect `retryAfterSeconds` |
| 12 | `requestRateLimited` | Yes | Respect `retryAfterSeconds` |
| 14 | `serverRecordChanged` | No | Merge and retry |
| 23 | `quotaExceeded` | No | Prompt user to free iCloud space |
| 25 | `limitExceeded` | No | Reduce batch size and retry |
| 26 | `zoneNotFound` | No | Create the zone first |
| 27 | `userDeletedZone` | No | Re-create zone, re-upload data |

## CloudKit Dashboard

**URL:** https://icloud.developer.apple.com/dashboard

### Key Capabilities

- **Schema browser:** View and edit record types, fields, and indexes
- **Records:** Query, create, edit, and delete records in any database scope
- **Telemetry:** Request count, error rate, latency (p50/p95/p99), bandwidth
- **Logs:** Individual request details and error traces
- **Subscriptions:** View active subscriptions
- **Notifications:** Set alerts for error rate spikes, quota thresholds, schema changes

### Development vs Production

CloudKit has separate development and production environments. Schema changes in development must be promoted to production via the Dashboard before release builds can use them. Promotion is one-way and cannot be undone.

**Critical gotcha:** If you add record types, fields, or indexes in Development but never deploy them to Production, queries in Production silently return empty results — no `CKError`, no crash, no clue. This is the #1 cause of "works in TestFlight but not App Store" bugs and costs 3-7 days in rejection cycles.

Before every App Store submission:
1. CloudKit Console > Select container
2. "Deploy Schema Changes" > Review > Deploy
3. Test with Production environment in Xcode scheme settings to verify queries return data

## Large Dataset Sync

| Dataset Size | Strategy | Notes |
|---|---|---|
| < 1,000 records | Default CKSyncEngine | Works out of the box |
| 1,000–10,000 | Batch initial sync | 200-record batches, show progress UI |
| 10,000+ | Pagination + background processing | Use BGProcessingTask for initial sync |
| 100,000+ | Server-side filtering | Only sync what user needs, lazy-load rest |

Initial sync is the bottleneck. After initial sync, CKSyncEngine's incremental approach handles large datasets efficiently because it only fetches deltas via change tokens.

```swift
// Batched initial sync
func performInitialSync(batchSize: Int = 200) async throws {
    var cursor: CKQueryOperation.Cursor? = nil

    repeat {
        let (results, nextCursor) = try await database.records(
            matching: query,
            resultsLimit: batchSize,
            desiredKeys: nil,
            continuationCursor: cursor
        )
        try await localStore.saveBatch(results.compactMap { try? $0.1.get() })
        cursor = nextCursor
    } while cursor != nil
}
```
