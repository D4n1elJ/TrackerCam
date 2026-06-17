# GeoToolbox & Place Descriptors

New framework for standardized place representation across mapping services.

```swift
import GeoToolbox
```

## PlaceDescriptor

```swift
// From address
let fountain = PlaceDescriptor(
    representations: [.address("121 James's St\nDublin 8\nIreland")],
    commonName: "Obelisk Fountain"
)

// From coordinates
let tower = PlaceDescriptor(
    representations: [.coordinate(CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945))],
    commonName: "Eiffel Tower"
)

// Multiple representations
let statue = PlaceDescriptor(
    representations: [
        .coordinate(CLLocationCoordinate2D(latitude: 40.6892, longitude: -74.0445)),
        .address("Liberty Island, New York, NY 10004")
    ],
    commonName: "Statue of Liberty"
)
```

## Accessing Properties

```swift
descriptor.commonName    // String?
descriptor.coordinate    // CLLocationCoordinate2D?
descriptor.address       // String?
```

## PlaceRepresentation

| Case | Content |
|---|---|
| `.coordinate(CLLocationCoordinate2D)` | Lat/lng location |
| `.address(String)` | Full address string |

## SupportingPlaceRepresentation

Proprietary identifiers from different mapping services:

```swift
let place = PlaceDescriptor(
    representations: [.coordinate(...)],
    commonName: "London Eye",
    supportingRepresentations: [
        .serviceIdentifiers([
            "com.apple.maps": "ABC123",
            "com.google.maps": "XYZ789"
        ])
    ]
)

place.serviceIdentifier(for: "com.apple.maps")  // "ABC123"
```

## MapKit Conversions

```swift
// MKMapItem → PlaceDescriptor
let descriptor = PlaceDescriptor(item: mapItem)

// PlaceDescriptor → MKMapItem
if let coord = descriptor.coordinate {
    let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
    let newItem = MKMapItem(location: location, address: MKAddress())
}
```

## Geocoding (New API)

### Forward Geocoding (Address → Coordinates)

```swift
guard let request = MKGeocodingRequest(addressString: "1 Apple Park Way, Cupertino") else { return }
let mapItems = try await request.mapItems
```

### Reverse Geocoding (Coordinates → Address)

```swift
let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
guard let request = MKReverseGeocodingRequest(location: location) else { return }
let mapItems = try await request.mapItems
```

### Creating PlaceDescriptor from Geocoding

```swift
let mapItems = try await geocodeAddress("1 Apple Park Way")
if let item = mapItems.first {
    let descriptor = PlaceDescriptor(item: item)
}
```

## When to Use

- Sharing place data between different mapping services
- Geocoding with new async API (replaces CLGeocoder for MapKit use cases)
- Standardized place interchange format
- Service-specific identifier management
