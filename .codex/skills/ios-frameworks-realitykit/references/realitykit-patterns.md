# RealityKit -- Patterns & API Reference

Complete reference for RealityKit covering ECS architecture, materials, physics, animation, audio, visionOS spatial features, iOS AR, Reality Composer Pro, and performance. All examples use Swift concurrency patterns.

---

## Entity-Component-System Architecture

### Entities

Entities are empty containers with identity and hierarchy. They hold components but have no behavior of their own.

```swift
// Empty entity
let entity = Entity()
entity.name = "player"

// ModelEntity convenience (has ModelComponent built in)
let box = ModelEntity(
    mesh: .generateBox(size: 0.1),
    materials: [SimpleMaterial(color: .red, isMetallic: true)]
)

// Async loading from bundle
let entity = try await Entity(named: "MyScene", in: .main)

// Async loading from URL
let entity = try await Entity(contentsOf: modelURL)

// Clone
let clone = entity.clone(recursive: true)
```

### Entity Subclasses

| Class | Purpose | Key Component |
|---|---|---|
| `Entity` | Base container | Transform only |
| `ModelEntity` | Renderable object | ModelComponent |
| `AnchorEntity` | AR anchor point | AnchoringComponent |
| `PerspectiveCamera` | Virtual camera | PerspectiveCameraComponent |
| `DirectionalLight` | Sun/directional light | DirectionalLightComponent |
| `PointLight` | Point light source | PointLightComponent |
| `SpotLight` | Spot light source | SpotLightComponent |
| `TriggerVolume` | Invisible collision zone | CollisionComponent |
| `ViewAttachmentEntity` | SwiftUI view in 3D (visionOS) | -- |

### Hierarchy

```swift
parent.addChild(child)
parent.addChild(child, preservingWorldTransform: true)
child.removeFromParent()

let found = root.findEntity(named: "player")

for child in entity.children {
    // Enumerate direct children
}
```

### Transform

```swift
// Local transform (relative to parent)
entity.position = SIMD3<Float>(0, 1, 0)
entity.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0))
entity.scale = SIMD3<Float>(repeating: 2.0)

// World-space
let worldPos = entity.position(relativeTo: nil)
entity.setPosition(SIMD3(1, 0, 0), relativeTo: nil)

// Look at target
entity.look(at: targetPosition, from: entity.position, relativeTo: nil)
```

**Coordinate system**: RealityKit uses meters. Y is up. -Z is forward (toward the screen/viewer).

---

## Components

### Built-in Component Catalog

| Component | Purpose |
|---|---|
| `Transform` | Position, rotation, scale |
| `ModelComponent` | Mesh geometry + materials |
| `CollisionComponent` | Collision shapes for physics and interaction |
| `PhysicsBodyComponent` | Mass, physics mode (dynamic/static/kinematic) |
| `PhysicsMotionComponent` | Linear and angular velocity |
| `CharacterControllerComponent` | Character physics controller |
| `AnchoringComponent` | AR anchor attachment |
| `SynchronizationComponent` | Multiplayer sync |
| `PerspectiveCameraComponent` | Camera settings |
| `DirectionalLightComponent` | Directional light |
| `PointLightComponent` | Point light |
| `SpotLightComponent` | Spot light |
| `SpatialAudioComponent` | 3D positional audio |
| `AmbientAudioComponent` | Non-positional audio |
| `ChannelAudioComponent` | Multi-channel audio |
| `OpacityComponent` | Entity transparency |
| `GroundingShadowComponent` | Contact shadow |
| `ImageBasedLightComponent` | Custom environment lighting |
| `ImageBasedLightReceiverComponent` | Receive IBL from source |
| `InputTargetComponent` | Gesture input (visionOS only) |
| `HoverEffectComponent` | Hover highlight (visionOS only) |
| `AccessibilityComponent` | VoiceOver support |

### Custom Components

```swift
struct HealthComponent: Component {
    var current: Int
    var maximum: Int
}

// Register before use (typically in app init)
HealthComponent.registerComponent()

// Attach
entity.components[HealthComponent.self] = HealthComponent(current: 100, maximum: 100)

// Read
if let health = entity.components[HealthComponent.self] {
    print(health.current)
}

// Modify (read-modify-write -- components are value types)
entity.components[HealthComponent.self]?.current -= 10
```

**Critical rule**: Components are structs. Reading a component gives you a copy. If you store it in a local variable, modify it, you must write it back:

```swift
var health = entity.components[HealthComponent.self]!
health.current -= damage
entity.components[HealthComponent.self] = health
```

---

## Systems

Systems contain per-frame logic. They query for entities with specific components and process them.

```swift
struct MovementSystem: System {
    static let query = EntityQuery(
        where: .has(VelocityComponent.self) && .has(Transform.self)
    )

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(
            matching: Self.query, updatingSystemWhen: .rendering
        ) {
            let velocity = entity.components[VelocityComponent.self]!
            entity.position += velocity.value * Float(context.deltaTime)
        }
    }
}

// Register before scene loads
MovementSystem.registerSystem()
```

### EntityQuery

```swift
// Single component
EntityQuery(where: .has(HealthComponent.self))

// Multiple required
EntityQuery(where: .has(HealthComponent.self) && .has(ModelComponent.self))

// Exclusion
EntityQuery(where: .has(EnemyComponent.self) && !.has(DeadComponent.self))
```

### System Rules

- One responsibility per system
- Query each frame -- never store entity references across frames
- Systems run in registration order -- register dependencies first
- Use `context.deltaTime` for frame-rate-independent movement

### Scene Events

```swift
scene.subscribe(to: CollisionEvents.Began.self) { event in
    let entityA = event.entityA
    let entityB = event.entityB
}

scene.subscribe(to: SceneEvents.Update.self) { event in
    let dt = event.deltaTime
}
```

| Event | Trigger |
|---|---|
| `SceneEvents.Update` | Every frame |
| `SceneEvents.DidAddEntity` | Entity added to scene |
| `SceneEvents.DidRemoveEntity` | Entity removed from scene |
| `SceneEvents.AnchoredStateChanged` | Anchor tracking changes |
| `CollisionEvents.Began` | Collision starts |
| `CollisionEvents.Updated` | Collision continues |
| `CollisionEvents.Ended` | Collision ends |
| `AnimationEvents.PlaybackCompleted` | Animation finishes |

---

## Materials

### Material Types

| Material | Purpose | When to Use |
|---|---|---|
| `SimpleMaterial` | Solid color or texture | Prototyping, simple objects |
| `PhysicallyBasedMaterial` | Full PBR pipeline | Production-quality rendering |
| `UnlitMaterial` | No lighting response | UI elements, always-visible markers |
| `OcclusionMaterial` | Invisible but occludes | AR: hiding 3D content behind real objects |
| `VideoMaterial` | Video playback on surface | Video on geometry |
| `ShaderGraphMaterial` | Custom shader graph | Reality Composer Pro authored shaders |
| `CustomMaterial` | Metal shader functions | Full Metal control |

### SimpleMaterial

```swift
var material = SimpleMaterial()
material.color = .init(tint: .blue)
material.metallic = .init(floatLiteral: 1.0)
material.roughness = .init(floatLiteral: 0.3)
```

### PhysicallyBasedMaterial

```swift
var material = PhysicallyBasedMaterial()
material.baseColor = .init(tint: .white,
    texture: .init(try .load(named: "albedo")))
material.metallic = .init(floatLiteral: 0.0)
material.roughness = .init(floatLiteral: 0.5)
material.normal = .init(texture: .init(try .load(named: "normal")))
material.ambientOcclusion = .init(texture: .init(try .load(named: "ao")))
material.emissiveColor = .init(color: .blue)
material.emissiveIntensity = 2.0
material.clearcoat = .init(floatLiteral: 0.8)
material.clearcoatRoughness = .init(floatLiteral: 0.1)
material.blending = .transparent(opacity: .init(floatLiteral: 0.5))
material.faceCulling = .back  // .none, .front, .back
```

**Metallic guidance**: Most real objects are metallic = 0.0. Only metals (gold, silver, chrome) should use metallic = 1.0.

### OcclusionMaterial (AR)

```swift
// Invisible plane that hides 3D content behind it
let occluder = ModelEntity(
    mesh: .generatePlane(width: 1, depth: 1),
    materials: [OcclusionMaterial()]
)
```

### TextureResource Loading

```swift
let texture = try await TextureResource(named: "texture")
let texture = try await TextureResource(contentsOf: url)

// With semantic hint
let texture = try await TextureResource(
    named: "texture",
    options: .init(semantic: .color)  // .color, .raw, .normal, .hdrColor
)
```

### MeshResource Built-in Generators

| Method | Parameters |
|---|---|
| `.generateBox(size:)` | `SIMD3<Float>` or single `Float` |
| `.generateBox(size:cornerRadius:)` | Rounded box |
| `.generateSphere(radius:)` | `Float` |
| `.generatePlane(width:depth:)` | Horizontal plane |
| `.generatePlane(width:height:)` | Vertical plane |
| `.generateCylinder(height:radius:)` | Cylinder |
| `.generateCone(height:radius:)` | Cone |
| `.generateText(_:)` | 3D text |

### Lighting

```swift
// Directional light with shadow
let light = DirectionalLight()
light.light = DirectionalLightComponent(
    color: .white, intensity: 1000, isRealWorldProxy: false
)
light.shadow = DirectionalLightComponent.Shadow(
    maximumDistance: 10, depthBias: 0.01
)

// Point light
let point = PointLight()
point.light = PointLightComponent(
    color: .white, intensity: 1000, attenuationRadius: 5
)

// Spot light
let spot = SpotLight()
spot.light = SpotLightComponent(
    color: .white, intensity: 1000,
    innerAngleInDegrees: 30, outerAngleInDegrees: 60,
    attenuationRadius: 10
)
```

**AR note**: In AR mode, RealityKit uses real-world lighting automatically. In non-AR scenes, you must provide lighting explicitly or the scene will be dark.

---

## Physics and Collision

### Collision Shapes

```swift
// Auto-generate from mesh (convenient but expensive)
entity.generateCollisionShapes(recursive: true)

// Manual shapes (prefer for performance)
entity.components[CollisionComponent.self] = CollisionComponent(
    shapes: [
        .generateBox(size: SIMD3(0.1, 0.2, 0.1)),
        .generateSphere(radius: 0.1),
        .generateCapsule(height: 0.3, radius: 0.05)
    ]
)
```

| Shape | Performance |
|---|---|
| `.generateBox(size:)` | Fastest |
| `.generateSphere(radius:)` | Fast |
| `.generateCapsule(height:radius:)` | Fast |
| `.generateConvex(from:)` | Moderate |
| `.generateStaticMesh(from:)` | Slowest (static only) |

### Physics Body

```swift
// Dynamic -- physics simulation controls movement
entity.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
    massProperties: .init(mass: 1.0),
    material: .generate(
        staticFriction: 0.5,
        dynamicFriction: 0.3,
        restitution: 0.4
    ),
    mode: .dynamic
)

// Static -- immovable collision surface
ground.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
    mode: .static
)

// Kinematic -- code-controlled, affects dynamic bodies
platform.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
    mode: .kinematic
)
```

| Mode | Behavior |
|---|---|
| `.dynamic` | Physics simulation controls position |
| `.static` | Immovable, participates in collisions |
| `.kinematic` | Code-controlled, pushes dynamic bodies |

**Rule**: Two `.static` bodies never collide. Physics interactions require at least one `.dynamic` body. Entities must share the same anchor for physics to work between them.

### Collision Groups and Filters

```swift
let playerGroup = CollisionGroup(rawValue: 1 << 0)
let enemyGroup = CollisionGroup(rawValue: 1 << 1)
let bulletGroup = CollisionGroup(rawValue: 1 << 2)

entity.components[CollisionComponent.self] = CollisionComponent(
    shapes: [.generateSphere(radius: 0.1)],
    filter: CollisionFilter(
        group: playerGroup,
        mask: enemyGroup | bulletGroup
    )
)
```

### Applying Forces

```swift
if var motion = entity.components[PhysicsMotionComponent.self] {
    motion.linearVelocity = SIMD3(0, 5, 0)
    entity.components[PhysicsMotionComponent.self] = motion
}
```

### Character Controller

```swift
entity.components[CharacterControllerComponent.self] =
    CharacterControllerComponent(
        radius: 0.3, height: 1.8,
        slopeLimit: .pi / 4, stepLimit: 0.3
    )

// Move with gravity
entity.moveCharacter(
    by: SIMD3(0.1, -0.01, 0),
    deltaTime: Float(context.deltaTime),
    relativeTo: nil
)
```

---

## Animation

### Transform Animation

```swift
entity.move(
    to: Transform(
        scale: SIMD3(repeating: 1.5),
        rotation: simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)),
        translation: SIMD3(0, 2, 0)
    ),
    relativeTo: entity.parent,
    duration: 2.0,
    timingFunction: .easeInOut
)
```

| Timing Function | Curve |
|---|---|
| `.default` | System default |
| `.linear` | Constant speed |
| `.easeIn` | Slow start |
| `.easeOut` | Slow end |
| `.easeInOut` | Slow start and end |

### USDZ Animations

```swift
if let entity = try? await Entity(named: "character") {
    for animation in entity.availableAnimations {
        entity.playAnimation(animation.repeat())
    }
}
```

### Animation Playback Control

```swift
let controller = entity.playAnimation(animation)
controller.pause()
controller.resume()
controller.stop()
controller.speed = 2.0       // 2x playback
controller.blendFactor = 0.5 // Blend with current state
controller.isComplete        // Check completion
```

### Repeating and Transitioning

```swift
let controller = entity.playAnimation(
    animation.repeat(count: 3),
    transitionDuration: 0.3,
    startsPaused: false
)
```

---

## Spatial Audio

### 3D Positional Audio

```swift
let resource = try AudioFileResource.load(
    named: "engine.wav",
    configuration: .init(shouldLoop: true)
)

let audioEntity = Entity()
audioEntity.components[SpatialAudioComponent.self] = SpatialAudioComponent(
    directivity: .beam(focus: 0.5),
    distanceAttenuation: .rolloff(factor: 1.0),
    gain: 0  // dB
)
audioEntity.position = SIMD3(2, 0, -1)
let controller = audioEntity.playAudio(resource)
```

### Ambient Audio

```swift
entity.components[AmbientAudioComponent.self] = AmbientAudioComponent(gain: -6)
entity.playAudio(backgroundMusic)
```

### Playback Control

```swift
let controller = entity.playAudio(resource)
controller.pause()
controller.stop()
controller.gain = -3    // Volume in dB
controller.speed = 1.5  // Pitch shift

entity.stopAllAudio()
```

---

## SwiftUI Integration

### RealityView

```swift
// Basic (iOS 18+, visionOS 1.0+)
RealityView { content in
    // make: called once to set up scene
    let box = ModelEntity(
        mesh: .generateBox(size: 0.1),
        materials: [SimpleMaterial(color: .blue, isMetallic: false)]
    )
    content.add(box)
} update: { content in
    // update: called when SwiftUI state changes
    // NOT called every frame -- use Systems for per-frame logic
}

// With placeholder during async loading
RealityView { content in
    if let entity = try? await Entity(named: "Scene") {
        content.add(entity)
    }
} placeholder: {
    ProgressView()
}
```

### RealityView with Attachments (visionOS)

```swift
RealityView { content, attachments in
    let sphere = ModelEntity(mesh: .generateSphere(radius: 0.1))
    content.add(sphere)

    if let label = attachments.entity(for: "priceTag") {
        label.position = SIMD3(0, 0.15, 0)
        sphere.addChild(label)
    }
} attachments: {
    Attachment(id: "priceTag") {
        Text("$9.99")
            .padding()
            .glassBackgroundEffect()
    }
}
```

### Model3D (Simple Display)

```swift
Model3D(named: "robot") { phase in
    switch phase {
    case .empty:
        ProgressView()
    case .success(let model):
        model.resizable().scaledToFit()
    case .failure(let error):
        Text("Failed: \(error.localizedDescription)")
    @unknown default:
        EmptyView()
    }
}
```

### Gesture Integration

```swift
RealityView { content in
    let entity = ModelEntity(mesh: .generateBox(size: 0.1))
    entity.generateCollisionShapes(recursive: true)
    entity.components.set(InputTargetComponent())  // visionOS
    content.add(entity)
}
.gesture(
    TapGesture()
        .targetedToAnyEntity()
        .onEnded { value in
            let tapped = value.entity
        }
)
.gesture(
    DragGesture()
        .targetedToAnyEntity()
        .onChanged { value in
            value.entity.position = value.convert(
                value.location3D, from: .local, to: .scene
            )
        }
)
```

**Gesture requirement**: Entity must have CollisionComponent. On visionOS, also needs InputTargetComponent. Gesture modifier goes on the RealityView, not a child view.

---

## Hand Tracking and Gestures (visionOS)

### Hand Tracking Provider

```swift
import ARKit

let session = ARKitSession()
let handTracking = HandTrackingProvider()

try await session.run([handTracking])

for await update in handTracking.anchorUpdates {
    let anchor = update.anchor
    guard anchor.isTracked else { continue }

    let skeleton = anchor.handSkeleton
    if let thumbTip = skeleton?.joint(.thumbTip),
       let indexTip = skeleton?.joint(.indexFingerTip) {
        let distance = simd_distance(
            thumbTip.anchorFromJointTransform.columns.3,
            indexTip.anchorFromJointTransform.columns.3
        )
        let isPinching = distance < 0.02  // 2cm threshold
    }
}
```

### System Gestures vs Custom

visionOS provides built-in gesture support through SwiftUI:
- **Tap**: `TapGesture().targetedToAnyEntity()`
- **Drag**: `DragGesture().targetedToAnyEntity()`
- **Rotate**: `RotateGesture().targetedToAnyEntity()`
- **Magnify**: `MagnifyGesture().targetedToAnyEntity()`

For custom hand tracking (beyond system gestures), use `HandTrackingProvider` from ARKit.

### InputTargetComponent

Required on visionOS for any entity that should respond to gestures:

```swift
entity.components[InputTargetComponent.self] = InputTargetComponent()
entity.components[CollisionComponent.self] = CollisionComponent(
    shapes: [.generateBox(size: SIMD3(0.1, 0.1, 0.1))]
)
```

### HoverEffectComponent

Adds a visual highlight when the user looks at an entity:

```swift
entity.components[HoverEffectComponent.self] = HoverEffectComponent()
```

---

## Immersive Spaces and Volumes (visionOS)

### Window vs Volume vs Immersive Space

| Container | Content | User Control |
|---|---|---|
| Window | 2D SwiftUI | User positions and resizes |
| Volume | 3D content in a bounded box | User positions; app controls size |
| Immersive Space | 3D content in shared/full space | App controls placement |

### Volume

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.5, height: 0.5, depth: 0.5, in: .meters)
    }
}
```

### Immersive Space

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        ImmersiveSpace(id: "solarSystem") {
            SolarSystemView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed, .full)
    }
}

// Open from a view
struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace

    var body: some View {
        Button("Enter Solar System") {
            Task {
                await openImmersiveSpace(id: "solarSystem")
            }
        }
    }
}
```

### Immersion Styles

| Style | Effect |
|---|---|
| `.mixed` | 3D content blends with passthrough (default) |
| `.progressive` | Gradually replaces passthrough |
| `.full` | Completely replaces real world |

### Ornaments

```swift
struct ContentView: View {
    var body: some View {
        RealityView { content in
            // 3D scene
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack {
                Button("Play") { }
                Button("Pause") { }
            }
            .padding()
            .glassBackgroundEffect()
        }
    }
}
```

---

## iOS AR Experiences

### AnchorEntity Types

```swift
// Horizontal surface (table, floor)
let anchor = AnchorEntity(
    .plane(.horizontal, classification: .table,
           minimumBounds: SIMD2(0.2, 0.2))
)

// Vertical surface (wall)
let anchor = AnchorEntity(
    .plane(.vertical, classification: .wall,
           minimumBounds: SIMD2(0.5, 0.5))
)

// World position
let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, -1))

// Image anchor
let anchor = AnchorEntity(
    .image(group: "AR Resources", name: "poster")
)

// Face anchor (front camera)
let anchor = AnchorEntity(.face)

// Body anchor
let anchor = AnchorEntity(.body)
```

### Plane Classifications

| Classification | Surface |
|---|---|
| `.table` | Table surface |
| `.floor` | Floor |
| `.ceiling` | Ceiling |
| `.wall` | Wall |
| `.door` | Door |
| `.window` | Window |
| `.seat` | Chair/couch |

### SpatialTrackingSession (iOS 18+)

```swift
let session = SpatialTrackingSession()
let config = SpatialTrackingSession.Configuration(
    tracking: [.plane, .object]
)
let result = await session.run(config)

if let notSupported = result {
    for denied in notSupported.deniedTrackingModes {
        print("Not supported: \(denied)")
    }
}
```

### AR Best Practices

- Anchor to detected surfaces, not world positions, for stability
- Use plane classification to place content appropriately
- Start with horizontal plane detection -- most reliable
- Test on real devices; simulator AR is limited
- Provide visual feedback during surface detection

---

## Reality Composer Pro Integration

Reality Composer Pro is Xcode's tool for authoring 3D scenes, materials, and animations.

### Loading Scenes

```swift
// Load a scene from a Reality Composer Pro project
if let scene = try? await Entity(named: "MyScene", in: .main) {
    content.add(scene)
}

// Find specific entities within the scene
if let robot = scene.findEntity(named: "Robot") {
    robot.components[SpinComponent.self] = SpinComponent()
}
```

### ShaderGraphMaterial

Author custom materials in Reality Composer Pro, then load at runtime:

```swift
if let entity = try? await Entity(named: "CustomObject") {
    // ShaderGraphMaterial is already applied from the .reality file
    content.add(entity)
}

// Modify shader parameters at runtime
if var material = entity.components[ModelComponent.self]?.materials.first
    as? ShaderGraphMaterial {
    try material.setParameter(name: "BaseColor", value: .color(.red))
    entity.components[ModelComponent.self]?.materials = [material]
}
```

### Asset Workflow

1. Create `.reality` files in Reality Composer Pro
2. Add to Xcode project as a Reality Composer Pro project
3. Load with `Entity(named:in:)` at runtime
4. Modify components programmatically as needed

---

## USDZ Loading and Asset Management

### Loading Models

```swift
// From bundle (preferred)
let entity = try await Entity(named: "robot", in: .main)

// From URL
let entity = try await Entity(contentsOf: modelURL)

// From ModelEntity convenience
let model = try await ModelEntity(named: "robot")
```

### Scale Issues

USDZ models may be authored in centimeters while RealityKit uses meters. If a model appears invisible or enormous:

```swift
// Check the model's scale
print("Scale: \(entity.scale)")
print("Bounds: \(entity.visualBounds(relativeTo: nil))")

// Fix centimeter-to-meter scale
entity.scale = SIMD3(repeating: 0.01)
```

### Asset Format Guidance

| Format | Support | Recommendation |
|---|---|---|
| `.usdz` | Full | Preferred for all 3D assets |
| `.reality` | Full | Reality Composer Pro scenes |
| `.usd` / `.usda` / `.usdc` | Load-time | Source formats, convert to USDZ for distribution |
| `.scn` | SceneKit only | Do not use with RealityKit |
| `.obj` / `.dae` | Limited | Convert to USDZ |

---

## Multiplayer

### Synchronization

```swift
// Components sync automatically if they conform to Codable
struct ScoreComponent: Component, Codable {
    var points: Int
}

// Mark entity for sync
entity.components[SynchronizationComponent.self] = SynchronizationComponent()
```

### MultipeerConnectivity

```swift
let service = try MultipeerConnectivityService(session: mcSession)
// Entities with SynchronizationComponent auto-sync across peers
```

### Ownership Rules

- Only the owner can modify a synced entity
- Request ownership before modifying shared entities
- Non-Codable component data does not sync

---

## Accessibility

```swift
var accessibility = AccessibilityComponent()
accessibility.label = "Red interactive cube"
accessibility.value = "Tap to activate"
accessibility.traits = .button
accessibility.isAccessibilityElement = true
entity.components[AccessibilityComponent.self] = accessibility
```

Always set AccessibilityComponent on interactive 3D elements for VoiceOver support.

---

## Performance

### Entity Count Guidelines

| Count | Action |
|---|---|
| Under 100 | No concerns |
| 100--1000 | Monitor with RealityKit debugger |
| 1000+ | Use instancing, LOD, and entity pooling |

### Instancing (Resource Sharing)

```swift
// Share mesh and material across many entities
let sharedMesh = MeshResource.generateSphere(radius: 0.01)
let sharedMaterial = SimpleMaterial(color: .white, isMetallic: false)

for i in 0..<1000 {
    let entity = ModelEntity(mesh: sharedMesh, materials: [sharedMaterial])
    entity.position = positions[i]
    parent.addChild(entity)
}
```

RealityKit automatically batches entities with identical mesh and material resources.

### Mesh LOD (Level of Detail)

For distant objects, use simpler meshes:

```swift
struct LODSystem: System {
    static let query = EntityQuery(where: .has(LODComponent.self))

    func update(context: SceneUpdateContext) {
        let cameraPos = /* get camera position */
        for entity in context.entities(
            matching: Self.query, updatingSystemWhen: .rendering
        ) {
            let distance = simd_distance(entity.position, cameraPos)
            let lod = entity.components[LODComponent.self]!

            if distance > lod.farThreshold {
                entity.components[ModelComponent.self]?.mesh = lod.lowMesh
            } else if distance > lod.nearThreshold {
                entity.components[ModelComponent.self]?.mesh = lod.midMesh
            } else {
                entity.components[ModelComponent.self]?.mesh = lod.highMesh
            }
        }
    }
}
```

### Texture Compression

- Keep USDZ files under 50MB for reliable loading on all devices
- Compress textures before bundling (ASTC format for iOS/visionOS)
- Use appropriate texture resolution -- 1024x1024 is sufficient for most objects
- Set correct texture semantic (.color, .raw, .normal) for proper compression

### Entity Pooling

Instead of creating/destroying entities, disable and reuse:

```swift
struct EntityPool {
    private var available: [Entity] = []

    mutating func acquire() -> Entity {
        if let entity = available.popLast() {
            entity.isEnabled = true
            return entity
        }
        return createNewEntity()
    }

    mutating func release(_ entity: Entity) {
        entity.isEnabled = false
        available.append(entity)
    }
}
```

### Collision Shape Optimization

- Use simple shapes (box, sphere, capsule) instead of mesh-based collision
- `generateCollisionShapes(recursive: true)` is convenient but expensive -- call once during setup
- For dynamic entities, always prefer manual simple shapes
- Static geometry: generate shapes once, never per-frame

### Profiling

Use Xcode's RealityKit debugger (Debug menu > Attach to Process):
- **Statistics overlay**: Entity count, draw calls, triangle count, FPS
- **Physics visualization**: Show collision shapes (`.showPhysics`)
- **Anchor visualization**: Show anchor positions and geometry

```swift
#if DEBUG
arView.debugOptions = [
    .showStatistics,
    .showPhysics,
    .showAnchorOrigins,
    .showAnchorGeometry
]
#endif
```

---

## Metal Integration

### RealityRenderer

For low-level Metal rendering of RealityKit content:

```swift
let renderer = try RealityRenderer()
renderer.entities.append(entity)

try renderer.render(
    viewMatrix: viewMatrix,
    projectionMatrix: projectionMatrix,
    size: size,
    colorTexture: colorTexture,
    depthTexture: depthTexture
)
```

---

## Diagnostics Quick Reference

| Symptom | First Check |
|---|---|
| Entity not visible | Has ModelComponent? Scale > 0? Position in front of camera (-Z)? |
| Gesture not responding | Has CollisionComponent? (+ InputTargetComponent on visionOS) |
| Anchor not tracking | Anchor type matches environment? Adequate lighting? |
| Frame rate dropping | Entity count? Resource sharing? Collision shape complexity? |
| Material too dark | Has lighting? In non-AR, add DirectionalLightComponent |
| Physics not colliding | Both have CollisionComponent? Same anchor? At least one dynamic? |
| USDZ invisible | Scale issue -- check bounds, try `scale = SIMD3(repeating: 0.01)` |
| Custom component ignored | Registered via `registerComponent()`? |
| System not running | Registered via `registerSystem()` before scene loads? |

### Visibility Diagnostic

```swift
func diagnoseVisibility(_ entity: Entity) {
    print("Name: \(entity.name)")
    print("Enabled: \(entity.isEnabled)")
    print("In hierarchy: \(entity.isEnabledInHierarchy)")
    print("Anchored: \(entity.isAnchored)")
    print("World position: \(entity.position(relativeTo: nil))")
    print("Scale: \(entity.scale)")
    print("Has model: \(entity.components[ModelComponent.self] != nil)")
}
```

### Gesture Diagnostic

```swift
func diagnoseGesture(_ entity: Entity) {
    print("Has collision: \(entity.components[CollisionComponent.self] != nil)")
    print("Has input target: \(entity.components[InputTargetComponent.self] != nil)")
    print("Enabled: \(entity.isEnabled)")
    if let collision = entity.components[CollisionComponent.self] {
        print("Collision shapes: \(collision.shapes.count)")
    }
}
```
