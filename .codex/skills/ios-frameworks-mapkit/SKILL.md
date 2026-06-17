---
name: ios-frameworks-mapkit
description: Use when implementing or debugging MapKit maps, annotations, clustering, search, directions, Look Around, or camera behavior.
---

# MapKit

Review and write MapKit code for correct API selection, annotation performance, and search/directions integration.

## Responsibility

**Owns:** SwiftUI Map and MKMapView selection, MapContentBuilder annotations, MapCameraPosition management, MKLocalSearch and MKLocalSearchCompleter, MKDirections routing, Look Around integration, annotation clustering, visible-region filtering, overlay rendering.

**Does NOT own:** Location authorization or monitoring (see core-location), server-side geospatial queries, custom tile server infrastructure.

## Core Principles

1. **Default to SwiftUI Map.** MKMapView via UIViewRepresentable costs 2-4 hours of boilerplate. SwiftUI Map handles markers, annotations, overlays, camera control, clustering, and selection. Only drop to MKMapView for custom tile overlays, advanced delegate control, or custom overlay renderers.
2. **Cluster before you scale.** 500+ unmanaged annotations produce overlapping pins, scroll lag, and memory spikes. Enable clustering with `.mapItemClusteringIdentifier` (SwiftUI) or `clusteringIdentifier` (MKMapView) before the count grows.
3. **Filter to the visible region.** Never load all annotations at once. Use `.onMapCameraChange(frequency: .onEnd)` to fetch or filter annotations within the visible `MKCoordinateRegion`.
4. **Configure search, don't replace it.** Empty or irrelevant MKLocalSearch results are almost always a configuration problem: missing `resultTypes`, missing `region` bias, or wrong query format. Fix configuration before reaching for a third-party SDK.
5. **Guard setRegion in updateUIView.** When wrapping MKMapView in UIViewRepresentable, calling `setRegion` without a guard creates an infinite loop: region change triggers delegate, delegate updates state, state triggers updateUIView.
6. **Request location auth before showing user location.** `UserAnnotation()` and `showsUserLocation` implicitly request authorization at display time with no context. Request authorization explicitly first via CLServiceSession.
7. **Reuse annotation views.** Without `dequeueReusableAnnotationView`, 1000 annotations = 1000 views in memory. With reuse, ~20-30 views recycle as the user scrolls.

## SwiftUI Map vs MKMapView Decision Tree

```
Need a map in your app?
|
+-- Standard markers, annotations, overlays, camera control, selection, clustering?
|   +-- YES --> SwiftUI Map (covers most apps)
|   +-- NO, need one of:
|       +-- Custom tile overlays (OpenStreetMap, custom imagery)
|       +-- Fine-grained delegate callbacks (willBeginLoadingMap, didFinishLoadingMap)
|       +-- Custom MKOverlayRenderer subclasses
|       +-- Custom annotation view animations beyond SwiftUI
|       --> MKMapView via UIViewRepresentable
```

## Annotation Count Decision Tree

```
How many annotations?
|
+-- < 100
|   Use Marker/Annotation directly in Map {} content builder.
|   No performance concern.
|
+-- 100-1000
|   Enable clustering.
|   SwiftUI: .mapItemClusteringIdentifier("poi")
|   MKMapView: view.clusteringIdentifier = "poi"
|
+-- 1000+
    Visible-region filtering + clustering.
    Fetch only annotations within the visible region via .onMapCameraChange.
    Consider server-side pre-clustering for datasets > 5K.
    MKMapView with view reuse is preferred for very large datasets.
```

## Search and Directions Strategy

```
Search:
+-- User typing (autocomplete) --> MKLocalSearchCompleter
|   Set resultTypes and region bias.
|   User selects result --> MKLocalSearch with the completion.
|
+-- Programmatic query ("nearest gas station") --> MKLocalSearch
    Set naturalLanguageQuery, region, resultTypes, pointOfInterestFilter.

Directions:
+-- MKDirections.Request (source + destination + transportType)
    --> MKDirections.calculate()
    --> MKRoute
        .polyline --> MapPolyline or MKPolylineRenderer
        .expectedTravelTime, .distance, .steps
```

## Pressure Scenarios

### "Just Wrap MKMapView in UIViewRepresentable"

**Pressure:** Developer knows MKMapView from UIKit. SwiftUI Map feels unfamiliar.

**Test:** Can you name a specific feature the app needs that SwiftUI Map cannot provide? If not, use SwiftUI Map.

**Without skill:** 200+ lines of UIViewRepresentable + Coordinator, manually bridging state, fighting updateUIView infinite loops -- when 20 lines of `Map {}` would work. **Cost: 2-4 hours wasted.**

### "Add All 10,000 Pins to the Map"

**Pressure:** PM wants users to see ALL locations.

**Without skill:** All 10K annotations at once. Unreadable overlapping blob, scroll lag, 200-400MB memory spike.

**With skill:** Clustering + visible-region filtering. Users see meaningful groups. Tap to expand. Only on-screen annotations rendered. **Cost avoided: unusable map + performance complaints.**

### "MapKit Search Is Broken, Add Google Maps SDK"

**Pressure:** MKLocalSearch returns irrelevant or empty results.

**Without skill:** Add Google Maps SDK (50+ MB binary, API key, billing). **Cost: 4-8 hours.**

**With skill:** Check configuration: set `resultTypes`, add `region` bias, use natural language query format. **Cost: 5 minutes.**

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| MKMapView when SwiftUI Map suffices | 2-4 hours UIViewRepresentable boilerplate | Use SwiftUI `Map {}` |
| Annotations created in view body | UI freeze, view recreation on every update | Move to `@State` or `@Observable` model |
| No annotation view reuse (MKMapView) | Memory spikes with 500+ annotations | `dequeueReusableAnnotationView(withIdentifier:for:)` |
| `setRegion` in `updateUIView` without guard | Infinite loop -- region change triggers update cycle | Guard with region equality check or coordinator flag |
| All 10K annotations loaded at once | Unreadable map, scroll lag, 200-400MB memory spike | Visible-region filtering + clustering |
| Ignoring `resultTypes` in MKLocalSearch | Irrelevant or empty results | Set `.resultTypes = [.pointOfInterest]` or `.address` |
| Showing user location without prior auth | Authorization prompt appears with no context | Request CLServiceSession first |
| Creating new MKLocalSearchCompleter per keystroke | Wasted resources, no throttling | Reuse one instance, set `queryFragment` |

## Pre-Ship Checklist

- [ ] Map loads and displays correctly
- [ ] Annotations appear at correct coordinates (lat/lng not swapped -- GeoJSON uses [lng, lat])
- [ ] Clustering enabled for 100+ annotations
- [ ] Visible-region filtering for 1000+ annotations
- [ ] Search returns relevant results (resultTypes and region configured)
- [ ] Camera position controllable programmatically via MapCameraPosition binding
- [ ] User location authorization requested before enabling UserAnnotation
- [ ] Directions render as MapPolyline overlay
- [ ] MKLocalSearchCompleter reused, not recreated per keystroke
- [ ] Annotation views reused via dequeue (MKMapView)
- [ ] No setRegion/updateUIView infinite loops (MKMapView)
- [ ] Look Around availability checked before display (MKLookAroundSceneRequest)
- [ ] Dark Mode renders correctly (map styles adapt automatically)
- [ ] Memory stable when scrolling/zooming with many annotations

## References

- `references/swiftui-map-patterns.md` -- SwiftUI Map, MapContentBuilder, camera, styles, search, directions, Look Around, iOS version matrix
- `references/performance-and-clustering.md` -- Clustering strategies, infinite loop prevention, visible-region filtering, MKMapView UIViewRepresentable integration
- `references/geotoolbox.md` -- GeoToolbox framework, PlaceDescriptor, MKGeocodingRequest, MKReverseGeocodingRequest, MKAddress
- `references/diagnostics.md` -- Symptom-based troubleshooting: annotations missing, region loops, clustering failures, search issues, coordinate confusion, console debugging
