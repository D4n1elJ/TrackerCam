# SceneKit Quick Reference

## Purpose

Opinionated guide for building and maintaining SceneKit 3D content. Covers scene setup, node hierarchy, materials, lighting, cameras, physics, animation, particles, model loading, SwiftUI integration, performance, and custom Metal shaders.

**Deprecation notice**: SceneKit is soft-deprecated as of iOS 26. Existing apps keep working and receive security patches, but no new features. `SceneView` (SwiftUI) is formally deprecated. All new 3D projects should start with RealityKit unless maintaining existing SceneKit code.

## How to Use

1. **Check the decision tree** -- confirm SceneKit is the right framework
2. **Set up scene and view** using the patterns below
3. **Check anti-patterns** before shipping
4. **For full API details**, read `references/scenekit-patterns.md`

## Framework Decision Tree

```
New project with 3D content?
|
+-- Need AR or visionOS?
|   YES -> RealityKit (SceneKit cannot target visionOS spatial)
|
+-- 2D sprites / tile maps?
|   YES -> SpriteKit
|
+-- Maintaining existing SceneKit codebase?
|   YES -> SceneKit (this guide). Plan migration path.
|
+-- Prototyping 3D quickly, no AR needed?
|   YES -> SceneKit is faster to prototype with.
|         Use USDZ assets so they port to RealityKit later.
|
+-- Production 3D app, shipping new?
    YES -> RealityKit. SceneKit receives no new features.
```

## Scene Setup

### UIKit (SCNView)

```swift
let sceneView = SCNView(frame: view.bounds)
sceneView.scene = SCNScene(named: "scene.usdz")
sceneView.allowsCameraControl = true
sceneView.showsStatistics = true // Always enable during development
sceneView.autoenablesDefaultLighting = true
view.addSubview(sceneView)
```

### SwiftUI (UIViewRepresentable)

`SceneView` is deprecated in iOS 26. Use a `UIViewRepresentable` wrapper instead:

```swift
struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
```

## Core Concepts at a Glance

| Concept | Key Type | What It Does |
|---|---|---|
| Scene | `SCNScene` | Root container; holds root node, background, fog, physics world |
| Node | `SCNNode` | Transform + optional geometry, light, camera, physics, particles |
| Geometry | `SCNBox`, `SCNSphere`, etc. | Shape with materials attached |
| Material | `SCNMaterial` | Surface appearance (PBR recommended via `.physicallyBased`) |
| Light | `SCNLight` | Illumination source (directional, omni, spot, area, ambient, probe, IES) |
| Camera | `SCNCamera` | Perspective/orthographic projection, DOF, HDR, motion blur |
| Physics | `SCNPhysicsBody` | Dynamic, static, or kinematic simulation |
| Action | `SCNAction` | Declarative animation sequences |
| Particles | `SCNParticleSystem` | GPU-accelerated particle effects |

## Coordinate System

Right-handed, Y-up:

```
     +Y (up)
      |
      +---- +X (right)
     /
   +Z (toward viewer)
```

Same as RealityKit -- spatial concepts transfer directly during migration.

## Material Setup (PBR)

```swift
let material = SCNMaterial()
material.lightingModel = .physicallyBased
material.diffuse.contents = UIColor.red       // or UIImage for texture
material.metalness.contents = 0.8
material.roughness.contents = 0.2
material.normal.contents = UIImage(named: "normal_map")
```

**Default choice**: Always use `.physicallyBased` lighting model. It matches RealityKit's default and produces realistic results.

## Animation Quick Reference

| Style | API | Best For |
|---|---|---|
| Declarative | `SCNAction` | Move, rotate, scale, fade, sequences, groups |
| Implicit | `SCNTransaction` | Animate property changes in a block |
| Explicit | `CABasicAnimation` | Keypath animations, infinite loops |
| File-based | `SCNAnimationPlayer` | Character animations from .dae/.usdz |

```swift
// Declarative sequence
let bounce = SCNAction.sequence([
    .moveBy(x: 0, y: 2, z: 0, duration: 0.3),
    .moveBy(x: 0, y: -2, z: 0, duration: 0.3)
])
node.runAction(bounce)

// Implicit animation
SCNTransaction.begin()
SCNTransaction.animationDuration = 0.5
node.position.y = 5
SCNTransaction.commit()
```

## Anti-Patterns

| Mistake | Fix |
|---|---|
| Starting a new project in SceneKit | Use RealityKit. SceneKit is deprecated. |
| Using `.scn` files | Convert to `.usdz` with `xcrun scntool --convert file.scn --format usdz` |
| Hundreds of nodes in a loop | Use `SCNParticleSystem` or `flattenedClone()` to reduce draw calls |
| Deep shader modifier investment | No portability to RealityKit -- keep it thin |
| Missing `showsStatistics = true` in dev | Always enable during development to catch frame drops early |
| Relying on `autoenablesDefaultLighting` in production | Add explicit lights for predictable results |
| Forgetting `[weak self]` in action completions | Retain cycles crash or leak |
| Not setting `categoryBitMask` on physics bodies | Default masks cause unexpected collision behavior |

## Model Loading

| Format | Extension | Portable to RealityKit |
|---|---|---|
| USD/USDZ | `.usdz`, `.usda`, `.usdc` | Yes -- preferred |
| Collada | `.dae` | No -- convert first |
| SceneKit Archive | `.scn` | No -- convert first |
| Wavefront OBJ | `.obj` | Geometry only |

**Rule**: Always use USDZ for new assets. Convert legacy formats early.

## Performance Rules

| Rule | Threshold |
|---|---|
| Draw calls | Keep under 100 per frame |
| Node count | Flatten with `flattenedClone()` when >50 similar nodes |
| Particle-like objects | Use `SCNParticleSystem`, not individual nodes |
| LOD | Add `SCNLevelOfDetail` for objects viewed at varying distances |
| Shadows | Limit shadow-casting lights to 1-2; reduce `shadowSampleCount` |
| Statistics | Keep `showsStatistics = true` during development |

## Full Reference

For the complete API -- node hierarchy, all light types, camera configuration, physics bodies and joints, collision detection, constraint system, particle systems, shader modifiers, SCNProgram, SCNTechnique, and performance optimization -- read `references/scenekit-patterns.md`.

For property-level SceneKit to RealityKit migration mapping -- read `references/scenekit-to-realitykit-migration.md`.

## Cross-References

| Topic | Skill |
|---|---|
| RealityKit (new 3D projects) | `realitykit` (if available) |
| SpriteKit (2D) | `spritekit` (if available) |
| Metal shaders | `metal` (if available) |
| SwiftUI view integration | `swiftui-patterns` |
