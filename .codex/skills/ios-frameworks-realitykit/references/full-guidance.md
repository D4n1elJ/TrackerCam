# RealityKit Quick Reference

## Purpose

Opinionated guide for building 3D content, AR experiences, and visionOS spatial apps with RealityKit's Entity-Component-System architecture. Covers iOS AR through visionOS immersive spaces.

## How to Use

1. **Pick the right framework** using the decision tree below
2. **Understand ECS** -- entities are containers, components are data, systems are logic
3. **Check anti-patterns** before shipping
4. **For full API and patterns**, read `references/realitykit-patterns.md`

## Framework Decision Tree

```
Need 3D content in your app?
  |
  +-- Building for visionOS?
  |     +-- YES -> RealityKit + RealityView (only option)
  |
  +-- New iOS AR experience?
  |     +-- YES -> RealityKit + RealityView (iOS 18+)
  |
  +-- Maintaining existing SceneKit code?
  |     +-- Minor fix -> Stay in SceneKit
  |     +-- New feature -> Migrate to RealityKit
  |
  +-- Need raw GPU / custom shaders?
  |     +-- YES -> Metal directly (or RealityKit + ShaderGraphMaterial)
  |
  +-- 2D game?
        +-- YES -> SpriteKit (not RealityKit)
```

| Framework | Status | Use Case |
|---|---|---|
| RealityKit | Active, Apple's focus | All new 3D/AR/spatial work |
| SceneKit | Maintenance mode | Legacy code only -- no new features |
| ARKit | Session layer for RealityKit | Provides tracking data; RealityKit renders |
| Metal | Low-level GPU | Custom rendering pipelines, compute shaders |

**Default choice**: RealityKit. SceneKit is soft-deprecated. Every line of SceneKit is migration debt.

## ECS Mental Model

RealityKit uses Entity-Component-System, not a scene graph. This is the single most important concept.

```
Entity (empty container with identity + hierarchy)
  +-- TransformComponent (position, rotation, scale)
  +-- ModelComponent (mesh + materials)
  +-- CollisionComponent (collision shapes)
  +-- PhysicsBodyComponent (mass, mode)
  +-- [YourCustomComponent] (app-specific data)

System (processes entities with specific components each frame)
```

| Scene Graph Thinking | ECS Thinking |
|---|---|
| "The player node moves" | "MovementSystem processes entities with VelocityComponent" |
| "Add a method to the node subclass" | "Add a component, create a system" |
| "Override update() in the node" | "Register a System that queries for components" |
| "The node knows its health" | "HealthComponent holds data, DamageSystem processes it" |

**Key rule**: Components are value types (structs). When you read one, you get a copy. You must write it back after modification.

## SwiftUI Integration Quick Reference

```swift
// Display 3D content (iOS 18+, visionOS 1.0+)
RealityView { content in
    let box = ModelEntity(
        mesh: .generateBox(size: 0.1),
        materials: [SimpleMaterial(color: .blue, isMetallic: false)]
    )
    content.add(box)
} update: { content in
    // Called when SwiftUI state changes (not every frame)
}

// Simple model display (no interaction needed)
Model3D(named: "toy_robot") { model in
    model.resizable().scaledToFit()
} placeholder: {
    ProgressView()
}
```

## Platform Quick Reference

| Feature | iOS | visionOS |
|---|---|---|
| RealityView | iOS 18+ | visionOS 1.0+ |
| Model3D | iOS 18+ | visionOS 1.0+ |
| AR anchors (plane, image, face) | iOS 13+ | N/A (room-scale) |
| Hand tracking | Via Vision framework | Native (HandTrackingProvider) |
| Immersive spaces | N/A | visionOS 1.0+ |
| Volumes | N/A | visionOS 1.0+ |
| SwiftUI Attachments | N/A | visionOS 1.0+ |
| InputTargetComponent | N/A | visionOS 1.0+ |
| Spatial audio | iOS 13+ | visionOS 1.0+ |

## Anti-Patterns

### Architecture

| Mistake | Fix |
|---|---|
| Subclassing Entity for behavior | Use components for data, systems for logic |
| Storing entity references in Systems | Query with EntityQuery each frame -- refs go stale |
| Timer-based movement instead of System | Use a System with `context.deltaTime` |
| All logic in RealityView closures | Extract to components and systems as complexity grows |

### Interaction

| Mistake | Fix |
|---|---|
| Interactive entity without CollisionComponent | Gestures require collision shapes -- always add them |
| visionOS entity without InputTargetComponent | Required for gesture input on visionOS |
| Gesture on a child view instead of RealityView | Attach `.gesture()` to the `RealityView` itself |
| Collision shape too small to tap | Use `.showPhysics` debug option; ensure reasonable size |

### Performance

| Mistake | Fix |
|---|---|
| Creating new ModelComponent every frame | Cache resources, only update when values change |
| Calling generateCollisionShapes every frame | Call once during setup |
| Mesh-based collision on dynamic entities | Use simple shapes (box, sphere, capsule) |
| Not sharing mesh/material across identical entities | Share resources -- RealityKit auto-batches matching entities |

### Materials

| Mistake | Fix |
|---|---|
| No lighting in non-AR scene | Add DirectionalLightComponent or environment resource |
| metallic = 1.0 on non-metal objects | Most real objects: metallic = 0.0 |
| Wrong texture semantic | .color for albedo, .raw for data maps, .normal for normals |
| Entity invisible after loading USDZ | Check scale (USD models may import in centimeters vs meters) |

## Common Patterns

### Tap-to-Place on Surface (iOS AR)

```swift
RealityView { content in
    let anchor = AnchorEntity(
        .plane(.horizontal, classification: .table,
               minimumBounds: SIMD2(0.2, 0.2))
    )
    let model = ModelEntity(
        mesh: .generateBox(size: 0.1),
        materials: [SimpleMaterial(color: .blue, isMetallic: false)]
    )
    model.generateCollisionShapes(recursive: true)
    anchor.addChild(model)
    content.add(anchor)
}
```

### Interactive Entity (visionOS)

```swift
RealityView { content in
    let sphere = ModelEntity(
        mesh: .generateSphere(radius: 0.1),
        materials: [SimpleMaterial(color: .red, isMetallic: true)]
    )
    sphere.generateCollisionShapes(recursive: true)
    sphere.components.set(InputTargetComponent())
    content.add(sphere)
}
.gesture(
    TapGesture()
        .targetedToAnyEntity()
        .onEnded { value in
            let tapped = value.entity
            // Handle tap
        }
)
```

### Custom Component + System

```swift
struct SpinComponent: Component {
    var radiansPerSecond: Float = 1.0
}

struct SpinSystem: System {
    static let query = EntityQuery(where: .has(SpinComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(
            matching: Self.query, updatingSystemWhen: .rendering
        ) {
            let spin = entity.components[SpinComponent.self]!
            let angle = spin.radiansPerSecond * Float(context.deltaTime)
            entity.orientation *= simd_quatf(
                angle: angle, axis: SIMD3(0, 1, 0)
            )
        }
    }
}

// Register in app init
SpinComponent.registerComponent()
SpinSystem.registerSystem()
```

## Code Review Checklist

- [ ] Custom components registered via `registerComponent()` before use
- [ ] Systems registered via `registerSystem()` before scene loads
- [ ] Components are value types (structs), not classes
- [ ] Read-modify-write pattern used for component updates
- [ ] Interactive entities have CollisionComponent
- [ ] visionOS interactive entities have InputTargetComponent
- [ ] Collision shapes are simple (box/sphere/capsule) where possible
- [ ] No entity references stored across frames in Systems
- [ ] Mesh and material resources shared across identical entities
- [ ] USD/USDZ format used for 3D assets (not .scn)
- [ ] Async loading used for model/scene loading
- [ ] AccessibilityComponent set on interactive 3D elements

## Full Reference

For complete coverage -- all component types, material system, physics, animation, audio, visionOS immersive spaces, hand tracking, Reality Composer Pro integration, performance optimization, and diagnostics -- read `references/realitykit-patterns.md`.

## Global Rules

| Rule | Value |
|---|---|
| Default framework for 3D | RealityKit (not SceneKit) |
| Architecture pattern | Entity-Component-System |
| Components | Structs (value types), never classes |
| Per-frame logic | Systems, never Timers |
| Interaction requirement | CollisionComponent (+ InputTargetComponent on visionOS) |
| Asset format | USDZ (not .scn, .obj, .dae) |
| Model loading | Always async (`try await Entity(named:)`) |
| Accessibility | Set AccessibilityComponent on interactive entities |
