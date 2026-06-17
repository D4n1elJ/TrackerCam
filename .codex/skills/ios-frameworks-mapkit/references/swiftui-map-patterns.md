# SwiftUI Map Patterns

## Map with MapContentBuilder

The standard pattern -- a map with markers, user location, and controls:

```swift
@State private var cameraPosition: MapCameraPosition = .automatic
@State private var selectedItem: MKMapItem?

Map(position: $cameraPosition, selection: $selectedItem) {
    UserAnnotation()

    ForEach(locations) { location in
        Marker(location.name, coordinate: location.coordinate)
            .tint(location.category.color)
    }
}
.mapStyle(.standard(elevation: .realistic))
.mapControls {
    MapUserLocationButton()
    MapCompass()
    MapScaleView()
}
.onChange(of: selectedItem) { _, item in
    if let item {
        handleSelection(item)
    }
}
```

Key points:
- `@State var cameraPosition` -- bind for programmatic camera control
- `selection: $selectedItem` -- handle tap on markers
- `MapCameraPosition.automatic` -- system manages initial view to show all content
- `.mapControls {}` -- built-in UI for location button, compass, scale
- `ForEach` in content builder -- dynamic annotations from data

## Marker

System-styled balloon marker with callout:

```swift
Marker("Coffee Shop", coordinate: coord)
Marker("Coffee Shop", systemImage: "cup.and.saucer.fill", coordinate: coord)
Marker("Coffee Shop", monogram: Text("CS"), coordinate: coord)
Marker("Coffee Shop", coordinate: coord)
    .tint(.brown)
Marker(item: mapItem)  // from MKMapItem
```

## Annotation

Fully custom SwiftUI view at a coordinate:

```swift
Annotation("Custom Pin", coordinate: coord) {
    VStack {
        Image(systemName: "mappin.circle.fill")
            .font(.title)
            .foregroundStyle(.red)
        Text("Here")
            .font(.caption)
    }
}

// Custom anchor point (default is bottom center)
Annotation("Pin", coordinate: coord, anchor: .center) {
    Circle()
        .fill(.blue)
        .frame(width: 20, height: 20)
}
```

## Shape Overlays

```swift
// Circle (radius in meters)
MapCircle(center: coord, radius: 1000)
    .foregroundStyle(.blue.opacity(0.2))
    .stroke(.blue, lineWidth: 2)

// Polygon
MapPolygon(coordinates: polygonCoords)
    .foregroundStyle(.green.opacity(0.3))
    .stroke(.green, lineWidth: 2)

// Polyline
MapPolyline(coordinates: routeCoords)
    .stroke(.blue, lineWidth: 4)

// From MKRoute
MapPolyline(route.polyline)
    .stroke(.blue, lineWidth: 5)
```

## Camera Position and Region Management

### MapCameraPosition Options

```swift
.automatic                                    // System manages to show all content
.region(MKCoordinateRegion(                   // Specific region
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
))
.camera(MapCamera(                            // Camera with pitch and heading
    centerCoordinate: coordinate,
    distance: 1000,                           // meters from center
    heading: 90,                              // degrees from north
    pitch: 60                                 // degrees from vertical
))
.userLocation(followsHeading: true, fallback: .automatic)
.item(mapItem)                                // Center on MKMapItem
.rect(MKMapRect(...))                         // Show specific rect
```

### Programmatic Camera Changes

```swift
withAnimation {
    cameraPosition = .region(newRegion)
}
```

### Keyframe Animation

```swift
Map(position: $cameraPosition)
    .mapCameraKeyframeAnimator(trigger: flyToTrigger) { initialCamera in
        KeyframeTrack(\.centerCoordinate) {
            LinearKeyframe(destination, duration: 2.0)
        }
        KeyframeTrack(\.distance) {
            CubicKeyframe(5000, duration: 1.0)
            CubicKeyframe(1000, duration: 1.0)
        }
    }
```

## onMapCameraChange

```swift
Map(position: $cameraPosition) { ... }
    .onMapCameraChange(frequency: .onEnd) { context in
        // context.region -- visible MKCoordinateRegion
        // context.camera -- current MapCamera
        // context.rect -- visible MKMapRect
        fetchAnnotations(in: context.region)
    }
```

Use `.onEnd` for data fetching (default). Use `.continuous` only when you need real-time tracking during gestures.

Do NOT set `cameraPosition` inside `onMapCameraChange` -- this creates a feedback loop.

## Map Styles

```swift
.mapStyle(.standard)                                                    // Default
.mapStyle(.standard(elevation: .realistic))                             // 3D buildings
.mapStyle(.standard(emphasis: .muted))                                  // Muted colors
.mapStyle(.standard(pointsOfInterest: .including([.restaurant, .cafe])))
.mapStyle(.imagery)                                                     // Satellite
.mapStyle(.imagery(elevation: .realistic))                              // 3D satellite
.mapStyle(.hybrid)                                                      // Satellite + labels
.mapStyle(.hybrid(elevation: .realistic))                               // 3D hybrid
```

## Interaction Modes

```swift
.mapInteractionModes(.all)           // Default -- all interactions
.mapInteractionModes([])             // Read-only map
.mapInteractionModes([.pan])         // Pan only, no zoom
.mapInteractionModes([.pan, .zoom])  // No rotate/pitch
```

## Look Around Integration

### Check Availability First

```swift
let request = MKLookAroundSceneRequest(coordinate: coordinate)
let scene = try? await request.scene
// scene is non-nil if Look Around is available at this coordinate
```

### Display Preview

```swift
@State private var lookAroundScene: MKLookAroundScene?

LookAroundPreview(scene: $lookAroundScene)
    .frame(height: 200)

func loadLookAround(for coordinate: CLLocationCoordinate2D) async {
    let request = MKLookAroundSceneRequest(coordinate: coordinate)
    lookAroundScene = try? await request.scene
}
```

### Static Snapshot

```swift
let snapshotter = MKLookAroundSnapshotter(scene: scene, options: .init())
let snapshot = try await snapshotter.snapshot
let image = snapshot.image
```

## Search with MKLocalSearch

### Autocomplete with MKLocalSearchCompleter

```swift
@Observable
class SearchModel {
    var searchText = ""
    var completions: [MKLocalSearchCompletion] = []
    var searchResults: [MKMapItem] = []

    private let completer = MKLocalSearchCompleter()
    private var completerDelegate: CompleterDelegate?

    init() {
        completerDelegate = CompleterDelegate { [weak self] results in
            self?.completions = results
        }
        completer.delegate = completerDelegate
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func updateSearch(_ text: String) {
        searchText = text
        completer.queryFragment = text  // completer debounces internally
    }

    func search(for completion: MKLocalSearchCompletion) async throws {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = [.pointOfInterest, .address]
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        searchResults = response.mapItems
    }

    func search(query: String, in region: MKCoordinateRegion) async throws {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        searchResults = response.mapItems
    }
}

class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    let onUpdate: ([MKLocalSearchCompletion]) -> Void

    init(onUpdate: @escaping ([MKLocalSearchCompletion]) -> Void) {
        self.onUpdate = onUpdate
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onUpdate(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Handle network issues, rate limiting
    }
}
```

### Rate Limiting Rules

- `MKLocalSearchCompleter` handles its own throttling -- set `queryFragment` on every keystroke, the completer debounces.
- Reuse one `MKLocalSearchCompleter` instance. Do not create a new one per query.
- Fire `MKLocalSearch` only when the user selects a completion or submits -- not on every keystroke.

### Result Types

```swift
request.resultTypes = .address            // Street addresses
request.resultTypes = .pointOfInterest    // Businesses, landmarks
request.resultTypes = .physicalFeature    // Mountains, lakes, parks
request.resultTypes = [.pointOfInterest, .address]  // Multiple types
```

### MKMapItem Properties

```swift
for item in response.mapItems {
    item.name                    // "Starbucks"
    item.placemark.coordinate    // CLLocationCoordinate2D
    item.placemark               // MKPlacemark with address components
    item.phoneNumber             // Optional phone
    item.url                     // Optional website
    item.pointOfInterestCategory // .cafe, .restaurant, etc.
}
```

## Directions with MKDirections

### Calculate Route

```swift
func calculateDirections(
    from source: CLLocationCoordinate2D,
    to destination: MKMapItem,
    transportType: MKDirectionsTransportType = .automobile
) async throws -> MKRoute {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
    request.destination = destination
    request.transportType = transportType
    request.requestsAlternateRoutes = true

    let directions = MKDirections(request: request)
    let response = try await directions.calculate()

    guard let route = response.routes.first else {
        throw MapError.noRouteFound
    }
    return route
}
```

### Display Route

```swift
Map(position: $cameraPosition) {
    if let route {
        MapPolyline(route.polyline)
            .stroke(.blue, lineWidth: 5)
    }
    Marker("Start", coordinate: startCoord)
    Marker("End", coordinate: endCoord)
}
```

### Route Information

```swift
let travelTime = route.expectedTravelTime  // TimeInterval in seconds
let distance = route.distance              // CLLocationDistance in meters
let steps = route.steps                    // [MKRoute.Step]

for step in steps {
    step.instructions    // "Turn right onto Main St"
    step.distance        // CLLocationDistance in meters
    step.polyline        // MKPolyline for this step's segment
}
```

### ETA Only (Faster)

```swift
let directions = MKDirections(request: request)
let eta = try await directions.calculateETA()
eta.expectedTravelTime     // TimeInterval
eta.distance               // CLLocationDistance
eta.expectedArrivalDate    // Date
eta.expectedDepartureDate  // Date
```

### Transport Types

```swift
.automobile    // Driving
.walking       // Pedestrian
.transit       // Public transit (where available)
.any           // All modes
```

## Map Snapshots

Generate static map images for sharing, thumbnails, or offline display:

```swift
let options = MKMapSnapshotter.Options()
options.region = MKCoordinateRegion(
    center: coordinate,
    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
)
options.size = CGSize(width: 300, height: 200)
options.scale = UIScreen.main.scale
options.mapType = .standard
options.pointOfInterestFilter = .excludingAll

let snapshotter = MKMapSnapshotter(options: options)
let snapshot = try await snapshotter.start()
let image = snapshot.image

// Convert coordinate to point in snapshot for custom drawing
let point = snapshot.point(for: coordinate)
```

## Geocoding (iOS 26+)

### MKGeocodingRequest -- Forward

```swift
guard let request = MKGeocodingRequest(addressString: "1 Apple Park Way, Cupertino, CA") else { return }
let mapItems = try await request.mapItems
```

### MKReverseGeocodingRequest -- Reverse

```swift
let location = CLLocation(latitude: 37.3349, longitude: -122.0090)
guard let request = MKReverseGeocodingRequest(location: location) else { return }
let mapItems = try await request.mapItems
```

### Geocoding vs Search

| Need | Use |
|---|---|
| Address string to coordinates | `MKGeocodingRequest` (iOS 26+) or `CLGeocoder` |
| Coordinates to address | `MKReverseGeocodingRequest` (iOS 26+) or `CLGeocoder` |
| Natural language place search | `MKLocalSearch` |
| Autocomplete suggestions | `MKLocalSearchCompleter` |

---

## iOS Version Feature Matrix

| Feature | iOS Version |
|---|---|
| SwiftUI Map (content builder) | 17.0+ |
| MapCameraPosition | 17.0+ |
| .mapSelection | 17.0+ |
| .mapCameraKeyframeAnimator | 17.0+ |
| .onMapCameraChange | 17.0+ |
| MapUserLocationButton, MapCompass, MapScaleView | 17.0+ |
| .mapInteractionModes | 17.0+ |
| LookAroundPreview (SwiftUI) | 17.0+ |
| MKLookAroundSceneRequest | 16.0+ |
| MKLocalSearch.ResultType.query | 18.0+ |
| GeoToolbox / PlaceDescriptor | 26.0+ |
| MKGeocodingRequest | 26.0+ |
| MKReverseGeocodingRequest | 26.0+ |
| MKAddress | 26.0+ |
