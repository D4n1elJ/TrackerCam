# MapKit Diagnostics

Symptom-based troubleshooting. Start with the symptom, follow the decision tree.

## Quick Reference

| Symptom | Check First | Common Fix |
|---|---|---|
| Annotations not appearing | Coordinate values (lat/lng swapped?) | Verify coordinate order, check delegate |
| Map region jumps/loops | updateUIView guard | Add region equality check or coordinator flag |
| Slow with many annotations | Annotation count, view reuse | Enable clustering, implement view reuse |
| Clustering not working | clusteringIdentifier set? | Set same identifier on all views |
| Overlays not rendering | renderer delegate method | Return correct MKOverlayRenderer subclass |
| Search returns no results | resultTypes, region bias | Set appropriate resultTypes and region |
| User location not showing | Authorization status | Request CLServiceSession first |
| Coordinates appear wrong | lat/lng order | MapKit uses (lat, lng); GeoJSON uses [lng, lat] |

---

## Annotations Not Appearing

```
Coordinates valid (not 0,0 or NaN)?
+-- NO --> Data source returning default/empty values. Validate before adding.
+-- YES
    |
    Lat/lng swapped? (Common with GeoJSON which uses [lng, lat])
    +-- YES --> CLLocationCoordinate2D(latitude: json[1], longitude: json[0])
    +-- NO
        |
        (SwiftUI) Annotations inside Map {} content builder?
        +-- NO --> Must be inside Map(position:) { Marker(...) }
        +-- YES
            |
            Map region showing the annotation coordinates?
            +-- NO --> Use .automatic camera or set region to fit annotations
            +-- YES --> Check displayPriority (.required for must-show)
```

---

## Region Jumping / Infinite Loops

```
(UIViewRepresentable) setRegion in updateUIView without guard?
+-- YES --> Classic infinite loop:
|   state change -> updateUIView -> setRegion -> regionDidChangeAnimated -> state change
|
|   Fix A: Guard with region equality
|     if mapView.region.center.latitude != region.center.latitude { ... }
|
|   Fix B: Coordinator flag
|     coordinator.isUpdating = true
|     mapView.setRegion(region, animated: true)
|     coordinator.isUpdating = false
|     // In regionDidChangeAnimated: guard !isUpdating
|
+-- NO
    |
    Multiple state sources fighting over region?
    +-- YES --> Single source of truth. One @State var cameraPosition.
    +-- NO
        |
        onMapCameraChange triggering state updates that move the camera?
        +-- YES --> Don't set cameraPosition inside onMapCameraChange
        +-- NO --> Check for animation conflicts (animated:true + SwiftUI animation)
```

---

## Performance Issues

```
Annotation count?
+-- > 500 without clustering --> Enable clustering
|   SwiftUI: .mapItemClusteringIdentifier("poi")
|   MKMapView: view.clusteringIdentifier = "poi"
|
+-- > 1000 --> Add visible-region filtering
|   .onMapCameraChange(frequency: .onEnd) { context in
|       visibleAnnotations = allLocations.filter { context.region.contains($0.coordinate) }
|   }
|
+-- < 500
    |
    (MKMapView) Using dequeueReusableAnnotationView?
    +-- NO --> Every annotation creates a new view. Register + dequeue.
    +-- YES
        |
        Complex custom annotation views?
        +-- YES --> Pre-render to UIImage or simplify to MKMarkerAnnotationView
        +-- NO
            |
            Overlays with 10K+ coordinate points?
            +-- YES --> Simplify geometry (Douglas-Peucker)
            +-- NO --> Profile with Instruments (Time Profiler, Allocations)
```

---

## Clustering Not Working

```
clusteringIdentifier set on annotation views?
+-- NO --> Required. SwiftUI: .mapItemClusteringIdentifier("poi")
+-- YES
    |
    All views using the SAME identifier?
    +-- NO --> Different identifiers = different cluster groups
    +-- YES
        |
        Too few annotations in visible area?
        +-- YES --> Clustering only activates when annotations physically overlap
        +-- NO
            |
            (MKMapView) Annotation view classes registered?
            +-- NO --> mapView.register(MKMarkerAnnotationView.self, ...)
            +-- YES --> Verify viewFor handles both MKClusterAnnotation and individual
```

---

## Overlays Not Rendering

```
(MKMapView) rendererFor delegate method implemented?
+-- NO --> Required. Without it, nothing renders.
+-- YES
    |
    Correct renderer subclass returned?
    +-- MKCircle needs MKCircleRenderer
    +-- MKPolyline needs MKPolylineRenderer
    +-- MKPolygon needs MKPolygonRenderer
    +-- Mismatch = crash or silent failure
    |
    Renderer styled? (strokeColor, fillColor, lineWidth)
    +-- NO --> Renderer exists but invisible. Set strokeColor + lineWidth.
    +-- YES
        |
        (SwiftUI) MapCircle/MapPolyline without .foregroundStyle or .stroke?
        +-- YES --> May render transparent. Add styling.
        +-- NO --> Check coordinates are within visible map region
```

---

## Search / Directions Failures

```
Network available?
+-- NO --> MapKit search requires connectivity
+-- YES
    |
    resultTypes too restrictive?
    +-- .physicalFeature but searching "Starbucks" --> Use .pointOfInterest
    +-- YES --> Combine: [.pointOfInterest, .address]
    +-- NO
        |
        Region bias missing?
        +-- NO region set --> Results from anywhere. Set request.region = visibleRegion
        +-- YES
            |
            Query format?
            +-- Structured (lat/lng, codes) --> Won't parse. Use natural language.
            |   Good: "coffee shops near San Francisco"
            |   Bad: "lat:37.7 lng:-122.4 coffee"
            +-- Natural language
                |
                Rate limited?
                +-- YES --> Throttle. Use MKLocalSearchCompleter for autocomplete.
                +-- NO
                    |
                    (Directions) Source/destination valid?
                    +-- nil --> Verify both are valid MKMapItem
                    +-- YES --> Check transportType (transit not available everywhere)
```

---

## User Location Not Showing

```
CLLocationManager.authorizationStatus?
+-- .notDetermined --> Request auth first: CLServiceSession(authorization: .whenInUse)
+-- .denied --> Show UI explaining value, link to Settings
+-- .restricted --> Parental controls. Cannot override.
+-- .authorizedWhenInUse / .authorizedAlways
    |
    (SwiftUI) UserAnnotation() in Map content?
    +-- NO --> Add it
    +-- YES
        |
        Running in Simulator without custom location?
        +-- YES --> Xcode: Debug > Simulate Location > pick a location
        +-- NO
            |
            Blue dot not on screen but location icon showing?
            +-- YES --> User outside visible region.
            |   Use MapCameraPosition.userLocation(fallback: .automatic)
            |   Or add MapUserLocationButton() in .mapControls
            +-- NO --> Check Settings > Privacy > Location Services for app
```

---

## Coordinate System Confusion

The #1 coordinate bug: swapping lat/lng when parsing GeoJSON.

| System | Order | Example |
|---|---|---|
| MapKit (CLLocationCoordinate2D) | latitude, longitude | `(latitude: 37.77, longitude: -122.42)` |
| GeoJSON | longitude, latitude | `[-122.42, 37.77]` |
| Google Maps | latitude, longitude | Same as MapKit |
| PostGIS ST_MakePoint | longitude, latitude | Same as GeoJSON |

```swift
// WRONG: Using GeoJSON order directly
let coord = CLLocationCoordinate2D(latitude: geoJson[0], longitude: geoJson[1])

// RIGHT: GeoJSON is [lng, lat], MapKit wants (lat, lng)
let coord = CLLocationCoordinate2D(latitude: geoJson[1], longitude: geoJson[0])
```

### Validation

```swift
func isValidCoordinate(_ coord: CLLocationCoordinate2D) -> Bool {
    coord.latitude >= -90 && coord.latitude <= 90
        && coord.longitude >= -180 && coord.longitude <= 180
        && !coord.latitude.isNaN && !coord.longitude.isNaN
}
```

If latitude > 90 or longitude > 180, coordinates are likely swapped.

---

## Console Debugging

```bash
# MapKit logs
log stream --predicate 'subsystem == "com.apple.MapKit"' --level debug

# Filter for your app
log stream --predicate 'process == "YourApp" AND (subsystem == "com.apple.MapKit" OR subsystem == "com.apple.CoreLocation")'
```

| Console Message | Meaning |
|---|---|
| `No renderer for overlay` | Missing rendererFor delegate method |
| `Reuse identifier not registered` | Call register before dequeue |
| `CLLocationManager authorizationStatus is denied` | User denied location |
