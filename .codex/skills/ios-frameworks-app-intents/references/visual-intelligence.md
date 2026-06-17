# Visual Intelligence Integration

Integrate your app with the system's visual search — users circle objects in the camera or onscreen and see matching results from your app.

```swift
import VisualIntelligence
import AppIntents
```

## IntentValueQuery — Camera/Screenshot Search

```swift
@UnionValue
enum VisualSearchResult {
    case landmark(LandmarkEntity)
    case collection(CollectionEntity)
}

struct LandmarkIntentValueQuery: IntentValueQuery {
    @Dependency var modelData: ModelData

    func values(for input: SemanticContentDescriptor) async throws -> [VisualSearchResult] {
        // Try labels first (text-based matching)
        if !input.labels.isEmpty {
            return try await modelData.search(matching: input.labels)
        }

        // Fall back to pixel buffer (image recognition)
        guard let pixelBuffer = input.pixelBuffer else { return [] }
        return try await modelData.search(matching: pixelBuffer)
    }
}
```

## SemanticContentDescriptor

| Property | Type | Use |
|---|---|---|
| `labels` | `[String]` | Classification labels for the circled object |
| `pixelBuffer` | `CVReadOnlyPixelBuffer?` | Raw visual data for image matching |

## On-Screen Entity Tagging

Associate visible content with app entities so users can ask Siri/ChatGPT about what's onscreen:

```swift
struct LandmarkDetailView: View {
    let landmark: LandmarkEntity

    var body: some View {
        ScrollView { /* content */ }
            .userActivity("com.landmarks.ViewingLandmark") { activity in
                activity.title = "Viewing \(landmark.name)"
                activity.appEntityIdentifier = EntityIdentifier(for: landmark)
            }
    }
}
```

## "More Results" Intent

Link to your app for the full result set:

```swift
struct ViewMoreLandmarksIntent: AppIntent, VisualIntelligenceSearchIntent {
    static var title: LocalizedStringResource = "View More Landmarks"

    @Parameter(title: "Semantic Content")
    var semanticContent: SemanticContentDescriptor

    func perform() async throws -> some IntentResult {
        // Open app search view with the semantic content
        return .result()
    }
}
```

## DisplayRepresentation for Results

Visual Intelligence uses your entity's display representation in search results:

```swift
struct LandmarkEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Landmark", table: "AppIntents"),
            numericFormat: "\(placeholder: .int) landmarks"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(location)",
            image: .init(named: thumbnailImageName)
        )
    }
}
```

## Best Practices

- Return results quickly — limit to 10-20 most relevant
- Use "More results" intent for additional items
- Include clear images in display representations
- Localize all text
- Implement deep linking for tapped results
- Search by labels for fast text matching, pixel buffer for visual matching
- Test on physical device with visual intelligence camera
