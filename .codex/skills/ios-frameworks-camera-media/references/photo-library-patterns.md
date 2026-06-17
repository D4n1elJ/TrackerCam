# Photo Library Patterns

## PhotosPicker (SwiftUI, iOS 16+)

No permission required. The system handles privacy out-of-process.

### Single Selection

```swift
import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?

    var body: some View {
        VStack {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images
            ) {
                Label("Select Photo", systemImage: "photo")
            }

            if let image = selectedImage {
                image.resizable().scaledToFit()
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await loadImage(from: newItem) }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else {
            selectedImage = nil
            return
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            selectedImage = Image(uiImage: uiImage)
        }
    }
}
```

### Multi-Selection

```swift
@State private var selectedItems: [PhotosPickerItem] = []

PhotosPicker(
    selection: $selectedItems,
    maxSelectionCount: 5,
    matching: .images
) {
    Text("Select Photos")
}
```

### Filters

```swift
.images                                          // Photos only
.videos                                          // Videos only
.livePhotos                                      // Live Photos
.screenshots                                     // Screenshots
.any(of: [.images, .videos])                     // Photos or videos
.all(of: [.images, .not(.screenshots)])          // Photos excluding screenshots
.all(of: [.images, .not(.any(of: [.screenshots, .panoramas]))])  // Compound exclusion
```

### HDR Preservation

By default, the picker may transcode to JPEG, losing HDR data. Use `.current` encoding to receive the original format:

```swift
PhotosPicker(
    selection: $selectedItems,
    matching: .images,
    preferredItemEncoding: .current  // Preserve HDR, no transcode
) { ... }
```

| Encoding | Behavior |
|---|---|
| `.automatic` | System decides format |
| `.current` | Original format, preserves HDR |
| `.compatible` | Force compatible format (may lose HDR) |

### Embedded Picker (iOS 17+)

Embed the picker inline instead of presenting as a sheet:

```swift
PhotosPicker(
    selection: $selectedItems,
    maxSelectionCount: 10,
    selectionBehavior: .continuous,  // Live updates as user taps
    matching: .images
) {
    Text("Select")
}
.photosPickerStyle(.inline)
.photosPickerDisabledCapabilities([.selectionActions])
.photosPickerAccessoryVisibility(.hidden, edges: .all)
.frame(height: 300)
```

| Style | Description |
|---|---|
| `.presentation` | Modal sheet (default) |
| `.inline` | Embedded in view hierarchy |
| `.compact` | Single row, minimal vertical space |

Disabled capabilities: `.search`, `.collectionNavigation`, `.stagingArea`, `.selectionActions`.

First time an embedded picker appears, iOS shows an onboarding UI explaining that your app can only access selected photos.

## PHPickerViewController (UIKit, iOS 14+)

No permission required. Use when building UIKit-based photo selection.

```swift
import PhotosUI

func showPicker() {
    var config = PHPickerConfiguration()
    config.selectionLimit = 1  // 0 = unlimited
    config.filter = .images

    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    present(picker, animated: true)
}

func picker(_ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard let result = results.first else { return }

    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
        guard let image = object as? UIImage else { return }
        DispatchQueue.main.async {
            self?.displayImage(image)
        }
    }
}
```

### UIKit HDR Preservation

```swift
var config = PHPickerConfiguration()
config.preferredAssetRepresentationMode = .current  // Don't transcode
```

## Custom Transferable for JPEG/HEIF

The default SwiftUI `Image` Transferable only supports PNG. Most photos from the camera roll are JPEG or HEIF. Use a custom Transferable to handle all image formats:

```swift
struct TransferableImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else {
                throw TransferError.importFailed
            }
            return TransferableImage(image: image)
        }
    }

    enum TransferError: Error {
        case importFailed
    }
}

// Usage
func loadImage(from item: PhotosPickerItem) async -> UIImage? {
    do {
        let result = try await item.loadTransferable(type: TransferableImage.self)
        return result?.image
    } catch {
        print("Failed to load image: \(error)")
        return nil
    }
}
```

## Limited Library Access

iOS 14+ users can grant access to a selected subset of their library. Authorization status `.limited` is valid and must be handled.

### Suppressing Automatic Prompt

By default, iOS shows "Select More Photos" every time `.limited` is detected. To handle it yourself:

```xml
<key>PHPhotoLibraryPreventAutomaticLimitedAccessAlert</key>
<true/>
```

### Checking and Requesting Access

```swift
import Photos

func checkAndRequestAccess() async -> PHAuthorizationStatus {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    switch status {
    case .notDetermined:
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    case .limited:
        await presentLimitedLibraryPicker()
        return .limited
    case .authorized:
        return .authorized
    case .denied, .restricted:
        return status
    @unknown default:
        return status
    }
}
```

### Presenting the Limited Library Picker

```swift
@MainActor
func presentLimitedLibraryPicker() {
    guard let windowScene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController else { return }

    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC)
}
```

### Permission Levels

| Level | What It Allows | How to Request |
|---|---|---|
| None needed | User picks via system picker | Use PhotosPicker / PHPicker |
| `.addOnly` | Save to camera roll, no reading | `requestAuthorization(for: .addOnly)` |
| `.limited` | User-selected subset only | User chooses in system UI |
| `.authorized` | Full library access | `requestAuthorization(for: .readWrite)` |

### Authorization Status Handling

```swift
let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
switch status {
case .authorized:
    showGallery()
case .limited:
    showGallery()        // Works with limited selection
    showLimitedBanner()  // Explain to user, offer to expand
case .denied, .restricted:
    showPermissionDenied()
case .notDetermined:
    requestAccess()
@unknown default:
    break
}
```

## Saving to Camera Roll

```swift
import Photos

func saveImageToLibrary(_ image: UIImage) async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
        throw PhotoError.permissionDenied
    }

    try await PHPhotoLibrary.shared().performChanges {
        PHAssetCreationRequest.creationRequestForAsset(from: image)
    }
}
```

Required Info.plist key:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save photos to your library</string>
```

For `.readWrite` access, also add:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Access your photos to share them</string>
```

## PHPhotoLibrary Change Observation

Keep gallery UI in sync with changes made in the Photos app or by other processes.

```swift
import Photos

class PhotoGalleryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var photos: [PHAsset] = []
    private var fetchResult: PHFetchResult<PHAsset>?

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        fetchPhotos()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func fetchPhotos() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 100
        fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        photos = fetchResult?.objects(at: IndexSet(0..<(fetchResult?.count ?? 0))) ?? []
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult,
              let changes = changeInstance.changeDetails(for: fetchResult) else { return }

        DispatchQueue.main.async {
            self.fetchResult = changes.fetchResultAfterChanges
            let newResult = changes.fetchResultAfterChanges
            self.photos = newResult.objects(at: IndexSet(0..<newResult.count))
        }
    }
}
```

## Asset Fetching and Caching

### Fetching Assets

```swift
// Recent photos
let options = PHFetchOptions()
options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
options.fetchLimit = 100
let recentPhotos = PHAsset.fetchAssets(with: .image, options: options)

// By identifier
let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
```

### Requesting Images from Assets

```swift
let manager = PHImageManager.default()
let options = PHImageRequestOptions()
options.deliveryMode = .highQualityFormat
options.resizeMode = .exact
options.isNetworkAccessAllowed = true  // For iCloud photos

manager.requestImage(
    for: asset,
    targetSize: CGSize(width: 300, height: 300),
    contentMode: .aspectFill,
    options: options
) { image, info in
    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
    if !isDegraded {
        // Final high-quality image
    }
}
```

### Delivery Modes

| Mode | Behavior |
|---|---|
| `.opportunistic` | Fast thumbnail first, then high quality |
| `.highQualityFormat` | Only high quality (may be slow for iCloud photos) |
| `.fastFormat` | Only fast/degraded |

### PHAsset Properties

| Property | Type | Description |
|---|---|---|
| `localIdentifier` | String | Unique ID |
| `mediaType` | PHAssetMediaType | `.image`, `.video`, `.audio` |
| `pixelWidth` / `pixelHeight` | Int | Dimensions |
| `creationDate` | Date? | When taken |
| `location` | CLLocation? | GPS location |
| `isFavorite` | Bool | Marked as favorite |

## Custom Albums

```swift
func getOrCreateAlbum(named title: String) async throws -> PHAssetCollection {
    let fetchOptions = PHFetchOptions()
    fetchOptions.predicate = NSPredicate(format: "title = %@", title)
    let existing = PHAssetCollection.fetchAssetCollections(
        with: .album, subtype: .any, options: fetchOptions)
    if let album = existing.firstObject { return album }

    var placeholder: PHObjectPlaceholder?
    try await PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCollectionChangeRequest
            .creationRequestForAssetCollection(withTitle: title)
        placeholder = request.placeholderForCreatedAssetCollection
    }

    guard let id = placeholder?.localIdentifier,
          let album = PHAssetCollection.fetchAssetCollections(
              withLocalIdentifiers: [id], options: nil).firstObject
    else { throw PhotoError.albumCreationFailed }

    return album
}

func saveToAlbum(_ image: UIImage, album: PHAssetCollection) async throws {
    try await PHPhotoLibrary.shared().performChanges {
        let assetRequest = PHAssetCreationRequest.creationRequestForAsset(from: image)
        guard let placeholder = assetRequest.placeholderForCreatedAsset,
              let albumRequest = PHAssetCollectionChangeRequest(for: album) else { return }
        albumRequest.addAssets([placeholder] as NSFastEnumeration)
    }
}
```
