# iOS File Storage

Decision framework for file-based storage — directory selection, capacity checking, backup exclusion, file protection, and diagnosing missing files. For structured/queryable data, use the SwiftData, GRDB, or CloudKit skill instead.

## Storage Decision Tree

```
What are you storing?

Structured data (queryable, relationships, search)
  → SwiftData, GRDB, or CloudKit — not this skill

Files → Which kind?
  ├─ User-created content (photos, documents, exports)
  │   → Documents/  (backed up, never purged, visible in Files app)
  │
  ├─ App-generated data that must persist (DB files, config, downloaded assets)
  │   → Library/Application Support/  (backed up, never purged)
  │
  ├─ Re-downloadable or regenerable content (thumbnails, API responses, images)
  │   → Library/Caches/  (not backed up, purged under storage pressure)
  │
  └─ Truly temporary (processing intermediates, export staging)
      → tmp/  (not backed up, purged aggressively — even while app runs)
```

## Directory Rules

| Directory | Backed Up | Purged | Use For |
|---|---|---|---|
| `Documents/` | Yes | Never | User-created content only |
| `Library/Application Support/` | Yes | Never | App data, DB files, downloaded assets |
| `Library/Caches/` | No | Under pressure | Anything re-downloadable or regenerable |
| `tmp/` | No | Aggressively | Short-lived intermediates |

**Key rule:** Never store re-downloadable content in `Documents/` — it bloats backups and risks App Store rejection.

## Backup Exclusion

Mark re-downloadable files in `Application Support/` as excluded from backup:

```swift
var values = URLResourceValues()
values.isExcludedFromBackup = true
try fileURL.setResourceValues(values)
```

Use when: downloaded media (podcasts, videos), server-fetched assets that persist but can be re-fetched. Files in `Caches/` are automatically excluded.

## Capacity Checking

Check before writing large files. Two thresholds:

| Key | Use For |
|---|---|
| `.volumeAvailableCapacityForImportantUsageKey` | Must-save data (user content, critical app data) |
| `.volumeAvailableCapacityForOpportunisticUsageKey` | Nice-to-have data (caches, pre-fetching) |

```swift
let values = try URL.homeDirectory.resourceValues(forKeys: [
    .volumeAvailableCapacityForImportantUsageKey
])
let available = values.volumeAvailableCapacityForImportantUsage ?? 0
guard fileSize < available else { /* show low-storage alert */ }
```

## File Protection Tiers

| Level | Accessible When | Use For |
|---|---|---|
| `.complete` | Only while unlocked | Passwords, tokens, health data |
| `.completeUnlessOpen` | After first unlock if already open | Active downloads |
| `.completeUntilFirstUserAuthentication` | After first unlock (default) | Most app data |
| `.none` | Always | Background fetch data, push payloads |

**Common mistake:** `.complete` protection blocks background task access. Use `.completeUntilFirstUserAuthentication` for files accessed in background.

## Diagnostics: Files Disappeared

```
Where was the file stored?

tmp/?
  → Expected. System purges on reboot or anytime. Move to Caches/ or App Support/.

Caches/?
  → Expected under storage pressure. Re-download on demand, or move to App Support/
    if it cannot be regenerated.

Documents/ or App Support/?
  → Not system-purged. Check: was the app deleted? Did a migration move files?
    Check file protection — .complete files are inaccessible when device is locked.
```

## Diagnostics: Backup Too Large

```
Check Documents/ size first.
  ├─ Large re-downloadable files? → Move to Caches/ or mark isExcludedFromBackup
  └─ User-created content? → Keep (warn user if >1 GB)

Check Application Support/ size.
  └─ Downloaded media? → Mark isExcludedFromBackup = true
```

## Diagnostics: File Inaccessible

```
Permission denied or empty read?
  ├─ Device locked + .complete protection? → Use .completeUntilFirstUserAuthentication
  ├─ Background task? → Same fix — .complete blocks background access
  └─ File exists but reads empty? → Check for zero-byte file from failed write
```

## File I/O Safety

Writing files incorrectly causes silent data corruption and crashes. These patterns are the most common sources of file-related bugs in iOS apps.

### TOCTOU Race (Check-Then-Act)

```swift
// WRONG: File can be deleted/moved between check and use.
if FileManager.default.fileExists(atPath: path) {
    let data = try Data(contentsOf: url)  // crash if removed between check and read
}

// RIGHT: Just attempt the operation and handle errors.
do {
    let data = try Data(contentsOf: url)
} catch CocoaError.fileReadNoSuchFile {
    // handle missing file
}
```

Never use `fileExists(atPath:)` followed by a read/write — the filesystem can change between the two calls.

### Concurrent File Writes

```swift
// WRONG: Two tasks writing the same file corrupt it.
Task { try data1.write(to: url) }
Task { try data2.write(to: url) }

// RIGHT: Write to a temporary file, then atomically replace.
try data.write(to: url, options: .atomic)
```

`.atomic` writes to a temporary file first and uses `rename(2)` to swap — which is atomic on APFS. For coordinated access across processes (e.g. App Groups), use `NSFileCoordinator`.

### Keychain Thread Safety

```swift
// WRONG: Concurrent keychain queries from multiple threads return errSecInteractionNotAllowed or stale values.
DispatchQueue.concurrentPerform(iterations: 10) { _ in
    SecItemCopyMatching(query, &result)  // unpredictable errors
}

// RIGHT: Serialize keychain access through an actor or serial queue.
actor KeychainStore {
    func read(query: CFDictionary) -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
```

### File Handle Leaks

```swift
// WRONG: Handle never closed on error path.
let handle = try FileHandle(forReadingFrom: url)
let data = handle.readDataToEndOfFile()
// if something throws above, handle leaks

// RIGHT: Use Data(contentsOf:) for simple reads, or ensure cleanup.
let data = try Data(contentsOf: url)
```

Prefer `Data(contentsOf:)` and `Data.write(to:)` over `FileHandle` for simple operations. If you need `FileHandle` for streaming, close it in a `defer` block.

## Cross-References

- Structured data persistence: `swiftdata`, `grdb`
- Cloud sync: `cloudkit` (CloudKit, iCloud Drive, NSUbiquitousKeyValueStore)
- Keychain (credentials, tokens): use Security framework directly
- App Groups (shared containers): use `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`
