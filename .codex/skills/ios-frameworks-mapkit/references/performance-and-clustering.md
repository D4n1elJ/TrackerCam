# Performance and Clustering

## Annotation Clustering Strategies by Count Tier

### < 100 Annotations

No clustering needed. Use Marker/Annotation directly in the Map content builder:

```swift
Map(position: $cameraPosition) {
    ForEach(locations) { location in
        Marker(location.name, coordinate: location.coordinate)
    }
}
```

### 100-1000 Annotations -- Enable Clustering

#### SwiftUI

```swift
Map(position: $cameraPosition) {
    ForEach(locations) { location in
        Marker(location.name, coordinate: location.coordinate)
            .tag(location.id)
    }
    .mapItemClusteringIdentifier("locations")
}
```

#### MKMapView

```swift
func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    if let cluster = annotation as? MKClusterAnnotation {
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: "cluster",
            for: annotation
        ) as! MKMarkerAnnotationView
        view.markerTintColor = .systemBlue
        view.glyphText = "\(cluster.memberAnnotations.count)"
        return view
    }

    let view = mapView.dequeueReusableAnnotationView(
        withIdentifier: "pin",
        for: annotation
    ) as! MKMarkerAnnotationView
    view.clusteringIdentifier = "locations"
    view.markerTintColor = .systemRed
    return view
}
```

Clustering requirements:
1. All annotation views that should cluster MUST share the same `clusteringIdentifier`.
2. Register annotation view classes in `makeUIView`: `mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")`.
3. Clustering only activates when annotations physically overlap at the current zoom level.
4. The system manages cluster/uncluster animation automatically.

### 1000+ Annotations -- Visible-Region Filtering + Clustering

Combine clustering with on-demand loading. Only display annotations within the visible map region:

```swift
struct MapView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var visibleAnnotations: [Location] = []

    let allLocations: [Location]

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(visibleAnnotations) { location in
                Marker(location.name, coordinate: location.coordinate)
            }
            .mapItemClusteringIdentifier("locations")
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleAnnotations = allLocations.filter { location in
                context.region.contains(location.coordinate)
            }
        }
    }
}
```

For datasets > 5K, consider server-side pre-clustering: send cluster centroids instead of individual points.

## MKCoordinateRegion.contains Extension

Required for visible-region filtering:

```swift
extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latRange = (center.latitude - span.latitudeDelta / 2)
            ...(center.latitude + span.latitudeDelta / 2)
        let lngRange = (center.longitude - span.longitudeDelta / 2)
            ...(center.longitude + span.longitudeDelta / 2)
        return latRange.contains(coordinate.latitude)
            && lngRange.contains(coordinate.longitude)
    }
}
```

Note: This simple check does not handle the antimeridian (International Date Line). For maps crossing longitude +/-180, use MKMapRect containment instead.

## setRegion / updateUIView Infinite Loop Prevention

When wrapping MKMapView in UIViewRepresentable, calling `setRegion` in `updateUIView` without a guard creates an infinite loop:

1. SwiftUI state changes --> `updateUIView` called
2. `updateUIView` calls `setRegion`
3. `setRegion` triggers `regionDidChangeAnimated` delegate
4. Delegate updates SwiftUI state --> back to step 1

### Fix: Coordinator Flag Pattern

```swift
struct MapViewWrapper: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Guard: only set region if this is a programmatic change, not a delegate echo
        guard !context.coordinator.isRegionChangeFromMap else { return }
        mapView.setRegion(region, animated: true)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWrapper
        var isRegionChangeFromMap = false

        init(_ parent: MapViewWrapper) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isRegionChangeFromMap = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            isRegionChangeFromMap = false
        }
    }
}
```

### Alternative: Region Equality Check

```swift
func updateUIView(_ mapView: MKMapView, context: Context) {
    if mapView.region.center.latitude != region.center.latitude
        || mapView.region.center.longitude != region.center.longitude {
        mapView.setRegion(region, animated: true)
    }
}
```

The coordinator flag pattern is more robust because the equality check can still loop when `setRegion` adjusts the span to fit the view's aspect ratio.

## MKMapView via UIViewRepresentable

Full pattern when SwiftUI Map is insufficient (custom tile overlays, advanced delegate control):

```swift
struct MapViewWrapper: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let annotations: [MyAnnotation]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "marker"
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Region -- guard against infinite loops
        guard !context.coordinator.isRegionChangeFromMap else { return }
        mapView.setRegion(region, animated: true)

        // Annotations -- diff instead of remove-all/add-all
        let current = Set(mapView.annotations.compactMap { $0 as? MyAnnotation })
        let desired = Set(annotations)
        mapView.addAnnotations(Array(desired.subtracting(current)))
        mapView.removeAnnotations(Array(current.subtracting(desired)))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
    }
}
```

Key rules for UIViewRepresentable map wrappers:
- **Diff annotations** in `updateUIView` instead of removing all and re-adding. Remove-all causes visible flicker.
- **Register annotation view classes** once in `makeUIView`, not in `updateUIView`.
- **Clean up** in `dismantleUIView` to release overlay renderers and annotation views.
- **Set delegate** to `context.coordinator` in `makeUIView`.

## Annotation View Reuse (MKMapView)

Without reuse, each annotation allocates its own view. With 1000 annotations, that is 1000 views in memory. With reuse, ~20-30 views recycle as the user scrolls.

```swift
// Register once in makeUIView
mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "marker")

// Dequeue in delegate
func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard !(annotation is MKUserLocation) else { return nil }

    let view = mapView.dequeueReusableAnnotationView(
        withIdentifier: "marker",
        for: annotation
    ) as! MKMarkerAnnotationView
    view.markerTintColor = .systemRed
    view.clusteringIdentifier = "poi"
    view.canShowCallout = true
    return view
}
```

## Tile Overlay Performance

When using custom tile overlays (e.g., OpenStreetMap):

```swift
let template = "https://tile.example.com/{z}/{x}/{y}.png"
let tileOverlay = MKTileOverlay(urlTemplate: template)
tileOverlay.canReplaceMapContent = true  // hides Apple Maps base layer
mapView.addOverlay(tileOverlay, level: .aboveLabels)
```

Performance considerations:
- Tile overlays load asynchronously per visible tile. Network latency directly affects rendering speed.
- `canReplaceMapContent = true` avoids rendering both the Apple base map and the custom tiles, saving GPU work.
- For offline tiles, subclass `MKTileOverlay` and override `loadTile(at:result:)` to serve from local storage.

## Overlay Rendering (MKMapView)

Overlays require a renderer delegate method. Without it, overlays are silently invisible.

```swift
func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    switch overlay {
    case let circle as MKCircle:
        let renderer = MKCircleRenderer(circle: circle)
        renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.2)
        renderer.strokeColor = .systemBlue
        renderer.lineWidth = 2
        return renderer

    case let polyline as MKPolyline:
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = .systemBlue
        renderer.lineWidth = 4
        return renderer

    case let polygon as MKPolygon:
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.3)
        renderer.strokeColor = .systemGreen
        renderer.lineWidth = 2
        return renderer

    case let tile as MKTileOverlay:
        return MKTileOverlayRenderer(tileOverlay: tile)

    default:
        return MKOverlayRenderer(overlay: overlay)
    }
}
```

For polylines/polygons with 10K+ points, simplify geometry (Douglas-Peucker algorithm) or reduce detail at low zoom levels.

## Gradient Polyline

```swift
let renderer = MKGradientPolylineRenderer(polyline: polyline)
renderer.setColors([.green, .yellow, .red], locations: [0.0, 0.5, 1.0])
renderer.lineWidth = 6
```

## Coordinate System Traps

| System | Order |
|---|---|
| MapKit (CLLocationCoordinate2D) | latitude, longitude |
| GeoJSON | longitude, latitude |
| PostGIS ST_MakePoint | longitude, latitude |

The most common coordinate bug is swapping lat/lng when parsing GeoJSON:

```swift
// WRONG -- GeoJSON[0] is longitude
let wrong = CLLocationCoordinate2D(latitude: geoJSON[0], longitude: geoJSON[1])

// RIGHT -- swap the indices
let right = CLLocationCoordinate2D(latitude: geoJSON[1], longitude: geoJSON[0])
```

Sanity check: latitude is -90 to 90, longitude is -180 to 180. If latitude > 90, the values are swapped.
