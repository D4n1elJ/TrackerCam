# 3D Charts

All 3D chart APIs require `import Charts`. Available on iOS 26+, visionOS.

## Chart3D

```swift
Chart3D {
    SurfacePlot(
        x: "X Axis",
        y: "Y Axis",
        z: "Z Axis",
        function: { x, y in sin(x) * cos(y) }
    )
}
```

## Viewing Angle (Chart3DPose)

### Read-Only Pose

```swift
Chart3D { ... }
    .chart3DPose(.front)
```

### Interactive Pose (User Can Rotate)

```swift
@State private var pose: Chart3DPose = .default

Chart3D { ... }
    .chart3DPose($pose)
```

### Predefined Poses

| Pose | View |
|---|---|
| `.default` | Standard angle |
| `.front` | Forward-facing |
| `.back` | Rear-facing |
| `.top` | Birds-eye |
| `.bottom` | Underneath |
| `.left` | Left side |
| `.right` | Right side |

### Custom Pose

```swift
Chart3DPose(azimuth: .degrees(45), inclination: .degrees(30))
```

### Animated Pose Changes

```swift
Button("Top View") {
    withAnimation { pose = .top }
}
```

## Camera Projection

```swift
Chart3D { ... }
    .chart3DCameraProjection(.perspective)    // Objects shrink with distance
    .chart3DCameraProjection(.orthographic)   // Uniform size regardless of depth
    .chart3DCameraProjection(.automatic)      // System decides
```

## SurfacePlot

### Function-Based Surface

```swift
SurfacePlot(
    x: "X",
    y: "Height",
    z: "Z",
    function: { x, z in sin(sqrt(x * x + z * z)) }
)
```

### Height-Based Colouring

```swift
SurfacePlot(x: "X", y: "Y", z: "Z", function: { x, z in sin(x) * cos(z) })
    .foregroundStyle(Chart3DSurfaceStyle.heightBased(yRange: -1.0...1.0))
```

### Custom Gradient Colouring

```swift
let gradient = Gradient(colors: [.blue, .cyan, .green, .yellow, .orange, .red])

SurfacePlot(x: "X", y: "Y", z: "Z", function: { x, z in sin(x) * cos(z) })
    .foregroundStyle(Chart3DSurfaceStyle.heightBased(gradient, yRange: -1.0...1.0))
```

### Normal-Based Colouring

```swift
SurfacePlot(...)
    .foregroundStyle(Chart3DSurfaceStyle.normalBased)
```

### Surface Roughness

```swift
SurfacePlot(...)
    .roughness(0.3)  // 0 = smooth, 1 = fully rough
```

## Multiple Surfaces

```swift
Chart3D {
    SurfacePlot(x: "X", y: "Y", z: "Z", function: { x, z in sin(x) * cos(z) })
        .foregroundStyle(.blue)

    SurfacePlot(x: "X", y: "Y", z: "Z", function: { x, z in cos(x) * sin(z) + 2 })
        .foregroundStyle(.red)
}
```

## RuleMark in Chart3D

```swift
Chart3D {
    SurfacePlot(...)
    RuleMark(x: .value("X", 0), y: .value("Y", 0), z: .value("Z", 0))
}
```

## Complete Interactive Example

```swift
struct Interactive3DSurface: View {
    @State private var pose: Chart3DPose = .default

    private let gradient = Gradient(colors: [.blue, .cyan, .green, .yellow, .orange, .red])

    var body: some View {
        VStack {
            Chart3D {
                SurfacePlot(
                    x: "X",
                    y: "Height",
                    z: "Z",
                    function: { x, z in
                        sin(sqrt(x * x + z * z)) / sqrt(x * x + z * z + 0.1)
                    }
                )
                .foregroundStyle(Chart3DSurfaceStyle.heightBased(gradient, yRange: -1.0...1.0))
                .roughness(0.2)
            }
            .chart3DPose($pose)
            .chart3DCameraProjection(.perspective)

            HStack {
                Button("Front") { withAnimation { pose = .front } }
                Button("Top") { withAnimation { pose = .top } }
                Button("Reset") { withAnimation { pose = .default } }
            }
            .buttonStyle(.bordered)
        }
    }
}
```

## Rendering Style

```swift
Chart3D { ... }
    .chart3DRenderingStyle(...)  // Chart3DRenderingStyle
```
