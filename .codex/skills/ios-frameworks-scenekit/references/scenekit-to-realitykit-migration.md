# SceneKit to RealityKit Migration Mapping

Property-level equivalence tables for migrating SceneKit code to RealityKit.

---

## Core Architecture

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNScene` | `RealityViewContent` / root `Entity` | RealityKit scenes are entity hierarchies |
| `SCNNode` | `Entity` | Lightweight container in both |
| `SCNView` | `RealityView` (SwiftUI) | No UIKit equivalent needed |
| `SceneView` (deprecated iOS 26) | `RealityView` | Direct replacement |
| `SCNRenderer` | `RealityRenderer` | Low-level Metal rendering |
| Node properties (geometry, light, etc.) | Components on Entity | ECS separates data from hierarchy |
| `SCNSceneRendererDelegate` | `System` / `SceneEvents.Update` | Frame-level updates |
| `.scn` files | `.usdz` / `.usda` files | Convert: `xcrun scntool --convert file.scn --format usdz` |

## Transforms and Hierarchy

| SceneKit | RealityKit | Notes |
|---|---|---|
| `node.position` | `entity.position` | Both SIMD3<Float> |
| `node.eulerAngles` | `entity.orientation` (quaternion) | RealityKit prefers quaternions |
| `node.scale` | `entity.scale` | Both SIMD3<Float> |
| `node.transform` | `entity.transform` | 4x4 matrix |
| `node.worldTransform` | `entity.transform(relativeTo: nil)` | World-space |
| `node.addChildNode(_:)` | `entity.addChild(_:)` | Same concept |
| `node.removeFromParentNode()` | `entity.removeFromParent()` | Same concept |
| `node.childNode(withName:recursively:)` | `entity.findEntity(named:)` | Named lookup |

## Geometry and Materials

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNGeometry` | `MeshResource` | Generate from code or load USD |
| `SCNBox`, `SCNSphere`, etc. | `MeshResource.generateBox()`, `.generateSphere()` | Similar built-in shapes |
| `SCNMaterial` | `SimpleMaterial`, `PhysicallyBasedMaterial` | PBR-first in RealityKit |
| `.diffuse` | `PhysicallyBasedMaterial.baseColor` | Different name |
| `.metalness` | `PhysicallyBasedMaterial.metallic` | Different name |
| `.roughness` | `.roughness` | Same concept |
| `.normal` | `.normal` | Same concept |
| Shader modifiers | `ShaderGraphMaterial` / `CustomMaterial` | No direct port -- must rewrite |
| `SCNProgram` | `CustomMaterial` with Metal functions | Different API surface |
| `SCNGeometrySource` | `MeshResource.Contents` | Low-level mesh data |

## Lighting

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNLight(.omni)` | `PointLightComponent` | Point light |
| `SCNLight(.directional)` | `DirectionalLightComponent` | Sun/directional |
| `SCNLight(.spot)` | `SpotLightComponent` | Cone light |
| `SCNLight(.area)` | No direct equivalent | Use multiple point lights |
| `SCNLight(.ambient)` | `EnvironmentResource` (IBL) | Image-based lighting preferred |
| `SCNLight(.probe)` | `EnvironmentResource` | Environment probes |
| `SCNLight(.IES)` | No direct equivalent | Use intensity profiles manually |

## Camera

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNCamera` | `PerspectiveCamera` entity | Entity with camera component |
| `camera.fieldOfView` | `PerspectiveCameraComponent.fieldOfViewInDegrees` | Same concept |
| `camera.zNear` / `camera.zFar` | `.near` / `.far` | Clipping planes |
| `camera.wantsDepthOfField` | Post-processing effects | Different mechanism |
| `allowsCameraControl` | Custom gesture handling | No built-in orbit camera in RealityKit |

## Physics

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNPhysicsBody` | `PhysicsBodyComponent` | Component-based |
| `.dynamic` / `.static` / `.kinematic` | Same modes | Same semantics |
| `SCNPhysicsShape` | `CollisionComponent` + `ShapeResource` | Separate from body in RealityKit |
| `categoryBitMask` | `CollisionGroup` | Named groups vs raw bitmasks |
| `collisionBitMask` | `CollisionFilter` | Filter-based |
| `contactTestBitMask` | `CollisionEvents.Began` subscription | Event-based contacts |
| `SCNPhysicsContactDelegate` | `scene.subscribe(to: CollisionEvents.Began.self)` | Combine-style events |
| `SCNPhysicsField` | Forces on `PhysicsBodyComponent` | Apply forces directly |
| `SCNPhysicsJoint` | `PhysicsJoint` | Similar joint types |

## Animation

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNAction` | `entity.move(to:relativeTo:duration:)` | Transform animation |
| `SCNAction.sequence` | Animation chaining | Less declarative in RealityKit |
| `SCNAction.group` | Parallel animations | Apply to different entities |
| `SCNAction.repeatForever` | `AnimationPlaybackController` repeat | Different API |
| `SCNTransaction` (implicit) | No equivalent | Explicit animations only |
| `CAAnimation` bridge | `entity.playAnimation()` | Load from USD |
| `SCNAnimationPlayer` | `AnimationPlaybackController` | Playback control |

## Interaction

| SceneKit | RealityKit | Notes |
|---|---|---|
| `hitTest(_:options:)` | `RealityViewContent.entities(at:)` | Different API |
| Gesture recognizers on SCNView | `ManipulationComponent` | Built-in drag/rotate/scale |

## Constraints

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNLookAtConstraint` | `entity.look(at:from:relativeTo:)` | Call in System update |
| `SCNBillboardConstraint` | Manual in System | Calculate each frame |
| `SCNDistanceConstraint` | Manual in System | Calculate each frame |
| `SCNIKConstraint` | No direct equivalent | Implement manually |

No constraint system in RealityKit. Implement equivalent behavior in a `System` update loop.

## Particles

| SceneKit | RealityKit | Notes |
|---|---|---|
| `SCNParticleSystem` | `ParticleEmitterComponent` | Component-based |
| Programmatic setup | Reality Composer Pro preferred | Visual authoring in RealityKit |
| `birthRate`, `particleLifeSpan` | Similar properties on component | Different API names |

## Migration Strategy

1. **Convert assets first** -- `.scn` to `.usdz` via `xcrun scntool`
2. **Migrate incrementally** -- new features in RealityKit, existing SceneKit stays
3. **Modularize** -- Swift packages per subsystem so they can be migrated independently
4. **Rewrite shaders** -- shader modifiers and SCNProgram have no portability; plan full rewrites
5. **Replace constraints** -- implement as `System` update logic in RealityKit
