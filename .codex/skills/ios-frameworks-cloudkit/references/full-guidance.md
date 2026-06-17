# CloudKit & iCloud

Review and write iCloud sync code for correctness, modern API usage, and production reliability.

## Responsibility

**Owns:** CloudKit databases (public, private, shared), CKRecord CRUD, CKSyncEngine, SwiftData+CloudKit integration, CKShare and collaboration, subscriptions and push notifications, iCloud Drive document sync, NSUbiquitousKeyValueStore, NSFileCoordinator, conflict resolution, sync diagnostics, CloudKit entitlements.

**Does NOT own:** Local-only persistence (see swiftdata/core-data skills), server-side API design, authentication token management, UI loading states (see swiftui-patterns).

## Core Principles

1. **Choose the right sync primitive.** CloudKit for structured data with relationships and queries. iCloud Drive for user-visible documents. NSUbiquitousKeyValueStore for tiny preferences. Mixing them up causes architectural pain.
2. **Offline-first always.** Write to local storage first, sync to cloud in the background. Never block UI on a network round-trip. Users on airplanes still need their data.
3. **CKSyncEngine for new CloudKit work.** Replaces manual CKDatabase fetch/push cycles. Handles change tokens, batching, account changes, and retry automatically.
4. **SwiftData+CloudKit is private-only.** It syncs to the private database automatically but does not support public databases, shared databases, or custom conflict resolution.
5. **Conflicts are inevitable.** Two devices editing the same record before syncing will conflict. Handle it explicitly or accept last-writer-wins. Never silently drop data.
6. **Fetch-then-modify-then-save.** When updating a CKRecord, always fetch the latest server version first. Saving a stale record triggers `serverRecordChanged` errors.
7. **Check per-record results in batch operations.** `CKModifyRecordsOperation` can partially fail. The operation-level result block misses individual record failures.

## Decision Tree

```
What needs syncing?

├── Structured data (records, relationships, queries)?
│   ├── Using SwiftData? → SwiftData + CloudKit (.private database)
│   │   └── Need public/shared database? → Cannot use SwiftData. Use CKSyncEngine.
│   ├── Custom persistence (GRDB, SQLite, JSON)?
│   │   └── CKSyncEngine (iOS 17+)
│   └── Need maximum control or pre-iOS 17?
│       └── Raw CKDatabase operations
│
├── User-visible documents (Files app)?
│   └── iCloud Drive (UIDocument + NSFileCoordinator)
│
├── Large binary files attached to records?
│   └── CKAsset (stored inside CloudKit, not user-visible)
│
└── Small preferences (<1 MB total)?
    └── NSUbiquitousKeyValueStore
```

### Which CloudKit Database?

```
Who needs access?

├── Only the current user, across their devices?
│   └── Private database (most common)
│
├── All users of the app?
│   └── Public database
│       └── Reads: no auth required. Writes: auth required.
│
└── Specific invited users?
    └── Shared database (CKShare)
        └── Records must be in a custom zone, not the default zone.
```

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Blocking UI on cloud fetch | App freezes on airplane mode | Read from local store, sync in background |
| Saving stale CKRecord | `serverRecordChanged` on every concurrent edit | Fetch latest record, modify it, then save |
| Ignoring `perRecordSaveBlock` | Batch partial failures go undetected | Check each record result individually |
| `@Attribute(.unique)` with SwiftData+CloudKit | CloudKit does not support unique constraints | Remove `.unique`, enforce uniqueness in app logic |
| Skipping conflict resolution | Silent data loss on multi-device edits | Implement merge or last-writer-wins explicitly |
| Nested NSFileCoordinator calls | Deadlock when coordinating iCloud Drive files | Single coordinator per operation, no nesting |
| Building custom sync instead of CKSyncEngine | Months of work reimplementing what Apple provides | Use CKSyncEngine for change tracking, retry, batching |
| Storing structured data in iCloud Drive as JSON | No queries, no relationships, manual conflict merge | Use CloudKit for structured data |
| NSUbiquitousKeyValueStore for large data | 1 MB total limit, 1024 key limit | Use CloudKit or iCloud Drive for anything substantial |
| CloudKit schema not deployed to Production | Queries silently return empty results — no error, no crash | Deploy schema in CloudKit Console before every App Store submission |
| Cloud-first writes (no local store) | App breaks on airplane mode, slow on bad network | Write to local store first, queue sync in background |

## Offline-First Architecture

All sync code must write locally first, then sync in the background. Never block UI on a network round-trip.

```swift
class OfflineFirstSync {
    private let localStore: LocalDatabase  // GRDB, SwiftData, etc.
    private let syncEngine: CKSyncEngine

    // Write to LOCAL first, queue sync in background
    func save(_ item: Item) async throws {
        try await localStore.save(item)
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(item.recordID)])
    }

    // Read from LOCAL (instant, works offline)
    func fetch() async throws -> [Item] {
        try await localStore.fetchAll()
    }
}
```

## Production Triage — Data Not Syncing After Update

When users report sync stopped working after an app update, run these steps in order:

1. **Check account status** (2 min) — `CKContainer.default().accountStatus()`. If `.noAccount`, user signed out.
2. **Verify entitlements unchanged** (5 min) — Compare old vs new build entitlements. Verify container IDs match.
3. **Check for schema deployment** (5 min) — Open CloudKit Console. Were schema changes deployed to Production? Queries silently return empty results if not.
4. **Check for breaking changes** (10 min) — Did record types change? Did required fields lose defaults? Are old and new app versions compatible?
5. **Test on clean device** (15 min) — Fresh install on a device signed into iCloud. Does sync work? If yes, the issue is migration-related.

**Root causes in 90% of cases:** Entitlements changed in build, container ID mismatch, schema not deployed to Production, or breaking schema change.

## Entitlement Checklist

Before sync will work:

1. **Xcode > Signing & Capabilities**
   - iCloud capability added
   - CloudKit checked (for CloudKit) or iCloud Documents checked (for iCloud Drive)
   - Container selected or created

2. **Apple Developer Portal**
   - App ID has iCloud capability
   - CloudKit container exists (for CloudKit)

3. **Device**
   - Signed into iCloud
   - iCloud Drive enabled (Settings > [Name] > iCloud)

## Sync Diagnostics — First Steps

90% of sync problems are account, entitlement, or network issues. Always check these before changing code:

```swift
// 1. Is iCloud available?
let token = FileManager.default.ubiquityIdentityToken  // nil = not signed in

// 2. CloudKit account status
let status = try await CKContainer.default().accountStatus()
// .available, .noAccount, .restricted, .temporarilyUnavailable

// 3. Container accessible?
if let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
    // iCloud container is reachable
}
```

### Common CKError Codes

| Error | Cause | Response |
|---|---|---|
| `.serverRecordChanged` | Stale record saved | Fetch latest, merge, retry |
| `.quotaExceeded` | User's iCloud storage full | Prompt user to free space |
| `.networkUnavailable` | No internet | Queue for retry when online |
| `.accountTemporarilyUnavailable` | Transient server issue | Retry with exponential backoff |
| `.zoneBusy` | Server throttling | Respect `retryAfterSeconds` in error |
| `.limitExceeded` | Too many records in one operation | Reduce batch size |
| `.partialFailure` | Some records in batch failed | Check `partialErrorsByItemID` |

## Pre-Ship Checklist

- [ ] Entitlements configured (iCloud, CloudKit or Documents, container ID)
- [ ] Offline-first: app works without network, syncs when available
- [ ] Conflict resolution implemented (at minimum last-writer-wins)
- [ ] Per-record error handling in batch operations
- [ ] Retry with exponential backoff on transient errors
- [ ] Account status checked before sync operations
- [ ] Sync state visible to user (synced, pending, error indicators)
- [ ] Tested with two devices on the same iCloud account
- [ ] Tested sign-out and sign-in to different account
- [ ] CloudKit Dashboard monitored for error rates and latency

## References

- `references/cloudkit-patterns.md` — CKContainer, CKRecord CRUD, subscriptions, CKShare, zones, error handling, CloudKit Dashboard
- `references/swiftdata-cloudkit.md` — SwiftData+CloudKit integration, NSPersistentCloudKitContainer, iCloud Drive documents, NSUbiquitousKeyValueStore, testing
