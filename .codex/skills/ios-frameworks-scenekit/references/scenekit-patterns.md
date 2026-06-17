# SceneKit Patterns Reference

Complete API reference for SceneKit scene graph, geometry, materials, lighting, cameras, animations, physics, particles, model loading, SwiftUI integration, performance, and custom Metal shaders.

---

## SCNScene and SCNView Setup

> **RealityKit:** `RealityView` replaces both `SCNView` and `SceneView`. No UIViewRepresentable needed.

### SCNScene

```swift
// From bundle
let scene = SCNScene(named: "model.usdz")!

// From URL with options
let scene = try SCNScene(url: modelURL, options: [
    .checkConsistency: true,
    .convertToYUp: true
])

// Programmatic
let scene = SCNScene()
```

**Scene properties:**

```swift
scene.rootNode                        // Root of node hierarchy
scene.background.contents            // Skybox: UIImage, UIColor, MDLSkyCubeTexture, or [UIImage] cubemap
scene.lightingEnvironment.contents    // IBL environment map (HDR image)
scene.lightingEnvironment.intensity   // IBL intensity multiplier
scene.fogStartDistance                // Linear fog near distance
scene.fogEndDistance                  // Linear fog far distance
scene.fogColor                       // Fog color (UIColor)
scene.fogDensityExponent             // Fog falloff curve
scene.isPaused                       // Pause all simulation and animation
scene.physicsWorld.gravity            // Default (0, -9.8, 0)
scene.physicsWorld.speed              // Simulation speed multiplier
```

### SCNView (UIKit)

```swift
let sceneView = SCNView(frame: view.bounds)
sceneView.scene = scene
sceneView.allowsCameraControl = true       // Built-in orbit/pan/zoom
sceneView.autoenablesDefaultLighting = true // Adds omni light if none exists
sceneView.showsStatistics = true           // FPS, draw calls, node count
sceneView.backgroundColor = .black
sceneView.antialiasingMode = .multisampling4X
sceneView.preferredFramesPerSecond = 60
sceneView.isTemporalAntialiasingEnabled = true
sceneView.isJitteringEnabled = true        // Required for TAA
```

**Debug options:**

```swift
sceneView.debugOptions = [
    .showPhysicsShapes,
    .showBoundingBoxes,
    .showLightInfluences,
    .showLightExtents,
    .renderAsWireframe,
    .showSkeletons,
    .showCreases,
    .showConstraints
]
```

### SceneView (SwiftUI) -- Deprecated iOS 26

```swift
// Still compiles but produces deprecation warning
SceneView(
    scene: scene,
    pointOfView: cameraNode,
    options: [.allowsCameraControl, .autoenablesDefaultLighting]
)
```

### UIViewRepresentable Wrapper (Recommended for SwiftUI)

```swift
struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    var allowsCameraControl = true
    var showsStatistics = false

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = allowsCameraControl
        view.autoenablesDefaultLighting = true
        view.showsStatistics = showsStatistics
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene = scene
    }
}
```

**Binding scene state to SwiftUI:**

```swift
struct InteractiveSceneView: UIViewRepresentable {
    let scene: SCNScene
    @Binding var selectedNodeName: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    class Coordinator: NSObject {
        let parent: InteractiveSceneView
        init(_ parent: InteractiveSceneView) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            let results = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            parent.selectedNodeName = results.first?.node.name
        }
    }
}
```

---

## Node Hierarchy

> **RealityKit:** `SCNNode` becomes `Entity`. `addChildNode` becomes `addChild`. `childNode(withName:recursively:)` becomes `findEntity(named:)`.

### SCNNode

```swift
let node = SCNNode()
let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
```

**Transform properties:**

```swift
node.position = SCNVector3(x, y, z)          // Local position
node.eulerAngles = SCNVector3(pitch, yaw, roll) // Rotation (radians)
node.scale = SCNVector3(1, 1, 1)             // Local scale
node.simdPosition = SIMD3<Float>(x, y, z)   // SIMD variants (preferred for math)
node.simdOrientation = simd_quatf(...)       // Quaternion rotation
node.pivot = SCNMatrix4MakeTranslation(0, -0.5, 0) // Offset pivot point

// World-space (read-only)
node.worldPosition                           // World position
node.worldTransform                          // Full world transform matrix
```

**Hierarchy:**

```swift
parent.addChildNode(child)
child.removeFromParentNode()
node.childNodes                              // Direct children
node.childNode(withName: "arm", recursively: true) // Named search
node.enumerateChildNodes { child, stop in
    // Visit each descendant
}
node.flattenedClone()                        // Merge geometry for performance
```

**Visibility and rendering:**

```swift
node.isHidden = false
node.opacity = 1.0                           // 0-1, affects children
node.castsShadow = true
node.renderingOrder = 0                      // Lower = rendered first (for transparency sorting)
node.categoryBitMask = 1                     // Used by lights and hit testing
```

### Built-in Geometries

```swift
SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.1)
SCNSphere(radius: 0.5)
SCNCylinder(radius: 0.3, height: 1)
SCNPlane(width: 2, height: 2)              // Single-sided by default
SCNTorus(ringRadius: 1, pipeRadius: 0.3)
SCNCapsule(capRadius: 0.3, height: 1)
SCNCone(topRadius: 0, bottomRadius: 0.5, height: 1)
SCNTube(innerRadius: 0.3, outerRadius: 0.5, height: 1)
SCNPyramid(width: 1, height: 1, length: 1)
SCNFloor()                                 // Infinite reflective ground plane
SCNText(string: "Hello", extrusionDepth: 0.2)
SCNShape(path: UIBezierPath, extrusionDepth: 0.1) // 2D path to 3D
```

**Segment counts** control tessellation:

```swift
let sphere = SCNSphere(radius: 1)
sphere.segmentCount = 48     // Higher = smoother, more triangles
```

### Custom Geometry from Vertex Data

```swift
let vertices: [SCNVector3] = [
    SCNVector3(0, 1, 0), SCNVector3(-1, 0, 0), SCNVector3(1, 0, 0)
]
let indices: [Int32] = [0, 1, 2]

let vertexSource = SCNGeometrySource(vertices: vertices)
let normalSource = SCNGeometrySource(normals: [SCNVector3(0, 0, 1), SCNVector3(0, 0, 1), SCNVector3(0, 0, 1)])
let uvSource = SCNGeometrySource(textureCoordinates: [CGPoint(x: 0.5, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)])

let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])
```

---

## Materials

> **RealityKit:** `SCNMaterial` becomes `PhysicallyBasedMaterial`. `.diffuse` maps to `.baseColor`, `.metalness` to `.metallic`. Shader modifiers have no direct port -- use `ShaderGraphMaterial` or `CustomMaterial`.

### Lighting Models

| Model | Description | Use Case |
|---|---|---|
| `.physicallyBased` | PBR metallic-roughness | Realistic rendering (recommended) |
| `.blinn` | Blinn-Phong specular | Simple shiny surfaces |
| `.phong` | Phong specular | Classic specular |
| `.lambert` | Diffuse only | Matte surfaces |
| `.constant` | Unlit, flat color | UI elements, debug |
| `.shadowOnly` | Invisible, receives shadows | AR ground plane |

### PBR Material Setup

```swift
let material = SCNMaterial()
material.lightingModel = .physicallyBased

// Texture maps or scalar values
material.diffuse.contents = UIImage(named: "albedo")      // Base color
material.metalness.contents = 0.0                          // 0 = dielectric, 1 = metal
material.roughness.contents = 0.5                          // 0 = mirror, 1 = rough
material.normal.contents = UIImage(named: "normal")        // Normal map
material.ambientOcclusion.contents = UIImage(named: "ao")  // AO map
material.emission.contents = UIColor.blue                  // Self-illumination / glow
material.displacement.contents = UIImage(named: "height")  // Displacement map
material.selfIllumination.contents = UIImage(named: "emit") // Emission map

// Rendering options
material.isDoubleSided = false
material.writesToDepthBuffer = true
material.readsFromDepthBuffer = true
material.blendMode = .alpha            // .add, .subtract, .multiply, .screen, .replace, .max
material.transparencyMode = .aOne      // .rgbZero for pre-multiplied alpha
material.cullMode = .back              // .front, .back (default)
material.fillMode = .fill             // .lines for wireframe
```

### Applying Materials

```swift
// Single material
node.geometry?.firstMaterial = material

// Multiple materials (one per geometry element)
node.geometry?.materials = [frontMaterial, sideMaterial, backMaterial]

// Replace specific slot
node.geometry?.material(named: "glass")?.diffuse.contents = UIColor.blue.withAlphaComponent(0.3)
```

### Texture Wrapping and Filtering

```swift
material.diffuse.wrapS = .repeat        // .clamp, .clampToBorder, .mirror
material.diffuse.wrapT = .repeat
material.diffuse.minificationFilter = .linear
material.diffuse.magnificationFilter = .linear
material.diffuse.mipFilter = .linear     // Enable mipmapping
material.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 2, 1) // Tile 2x
```

---

## Lighting

> **RealityKit:** Use `DirectionalLightComponent`, `PointLightComponent`, `SpotLightComponent`. No area/ambient/IES equivalents -- use `EnvironmentResource` for IBL.

### Light Types

| Type | Description | Shadows | Use Case |
|---|---|---|---|
| `.omni` | Point light, radiates in all directions | No | Lamps, candles |
| `.directional` | Parallel rays | Yes | Sun, moon |
| `.spot` | Cone-shaped beam | Yes | Flashlights, stage lights |
| `.area` | Rectangle emitter (soft shadows) | Yes | Window light, soft fill |
| `.ambient` | Uniform, directionless | No | Flat fill (prefer IBL instead) |
| `.probe` | Cubemap-based environment | No | Reflections, ambient color |
| `.IES` | Real-world photometric profile | Yes | Architectural lighting |

### Setting Up Lights

```swift
// Directional (sun)
let sunLight = SCNLight()
sunLight.type = .directional
sunLight.intensity = 1000               // Lumens
sunLight.color = UIColor.white
sunLight.castsShadow = true
sunLight.shadowRadius = 3               // Blur radius
sunLight.shadowSampleCount = 8          // Quality (higher = softer, slower)
sunLight.shadowMode = .deferred         // .forward for simple scenes
sunLight.shadowColor = UIColor(white: 0, alpha: 0.5)
sunLight.shadowMapSize = CGSize(width: 2048, height: 2048)
sunLight.maximumShadowDistance = 50     // Limit shadow range
sunLight.shadowCascadeCount = 3        // Cascaded shadow maps for large scenes
sunLight.shadowCascadeSplittingFactor = 0.15

let sunNode = SCNNode()
sunNode.light = sunLight
sunNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
scene.rootNode.addChildNode(sunNode)
```

```swift
// Spot light
let spotLight = SCNLight()
spotLight.type = .spot
spotLight.intensity = 2000
spotLight.spotInnerAngle = 20           // Full-brightness cone
spotLight.spotOuterAngle = 60           // Falloff cone
spotLight.attenuationStartDistance = 0
spotLight.attenuationEndDistance = 20
spotLight.attenuationFalloffExponent = 2
spotLight.castsShadow = true
```

### Environment / Image-Based Lighting (IBL)

```swift
scene.lightingEnvironment.contents = UIImage(named: "environment.hdr")
scene.lightingEnvironment.intensity = 1.5

// Skybox from same environment map
scene.background.contents = UIImage(named: "environment.hdr")
```

IBL provides ambient diffuse and specular reflections from an HDR image. Combine with one directional light for realistic results. Avoid adding `.ambient` lights when using IBL -- they flatten the image.

### Light Category Bitmasks

Control which nodes a light affects:

```swift
sunLight.categoryBitMask = 1       // Only affects nodes with matching category
playerNode.categoryBitMask = 1     // Lit by sun
uiNode.categoryBitMask = 2         // Not lit by sun
```

---

## Camera

### SCNCamera

```swift
let camera = SCNCamera()
camera.fieldOfView = 60                  // Degrees (perspective mode)
camera.zNear = 0.1                       // Near clipping plane
camera.zFar = 100                        // Far clipping plane
camera.usesOrthographicProjection = false // true for 2D-style view
camera.orthographicScale = 5             // Visible area in orthographic mode

let cameraNode = SCNNode()
cameraNode.camera = camera
cameraNode.position = SCNVector3(0, 5, 10)
cameraNode.look(at: SCNVector3.zero)      // Point camera at origin
scene.rootNode.addChildNode(cameraNode)
```

### Depth of Field

```swift
camera.wantsDepthOfField = true
camera.focusDistance = 5                  // Distance to focus plane
camera.focalLength = 50                  // Lens focal length (mm)
camera.fStop = 2.8                       // Aperture (lower = more blur)
camera.apertureBladeCount = 6            // Bokeh shape
```

### HDR and Post-Processing

```swift
camera.wantsHDR = true
camera.exposureOffset = 0                // EV adjustment
camera.minimumExposure = -3
camera.maximumExposure = 10
camera.whitePoint = 1.0
camera.averageGray = 0.18
camera.bloomIntensity = 0.5              // Glow on bright areas
camera.bloomThreshold = 0.8
camera.bloomBlurRadius = 10
camera.colorFringeIntensity = 0          // Chromatic aberration
camera.colorFringeStrength = 0
camera.motionBlurIntensity = 0.5         // Motion blur (0 = off)
camera.screenSpaceAmbientOcclusionIntensity = 1.0 // SSAO
camera.screenSpaceAmbientOcclusionRadius = 0.5
camera.screenSpaceAmbientOcclusionDepthThreshold = 0.2
camera.vignettingIntensity = 0.5         // Edge darkening
camera.vignettingPower = 2.0
camera.saturation = 1.0                  // Color saturation
camera.contrast = 0.0                    // Contrast adjustment
```

---

## Animations

> **RealityKit:** `SCNAction` becomes `entity.move(to:relativeTo:duration:)`. File-based animations use `entity.playAnimation()`. No implicit animation (`SCNTransaction`) equivalent.

### SCNAction (Declarative)

```swift
// Movement
SCNAction.move(by: SCNVector3(0, 2, 0), duration: 1)
SCNAction.move(to: SCNVector3(5, 0, 0), duration: 1)

// Rotation
SCNAction.rotateBy(x: 0, y: .pi, z: 0, duration: 1)
SCNAction.rotateTo(x: 0, y: .pi, z: 0, duration: 1)
SCNAction.rotate(by: .pi, around: SCNVector3(0, 1, 0), duration: 1)

// Scale
SCNAction.scale(by: 2, duration: 0.5)
SCNAction.scale(to: 0.5, duration: 0.5)

// Fade
SCNAction.fadeIn(duration: 0.5)
SCNAction.fadeOut(duration: 0.5)
SCNAction.fadeOpacity(to: 0.5, duration: 0.3)

// Composition
SCNAction.sequence([action1, action2])       // One after another
SCNAction.group([action1, action2])          // Simultaneously
SCNAction.repeat(action, count: 3)
SCNAction.repeatForever(action)
SCNAction.wait(duration: 1.0)

// Custom
SCNAction.run { node in /* one-shot code */ }
SCNAction.customAction(duration: 2.0) { node, elapsed in
    let progress = elapsed / 2.0
    node.opacity = 1.0 - CGFloat(progress)
}
```

**Running actions:**

```swift
node.runAction(action)
node.runAction(action, forKey: "myAnimation")
node.runAction(action) { /* completion */ }
node.removeAction(forKey: "myAnimation")
node.removeAllActions()
node.hasActions  // Check if running
```

**Timing modes:**

```swift
action.timingMode = .easeInEaseOut   // .linear, .easeIn, .easeOut
action.timingFunction = { t in t * t } // Custom curve
action.speed = 2.0                    // Playback speed multiplier
```

### Implicit Animation (SCNTransaction)

Animate any animatable property change within a transaction block:

```swift
SCNTransaction.begin()
SCNTransaction.animationDuration = 0.5
SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
SCNTransaction.completionBlock = { /* done */ }

node.position = SCNVector3(0, 5, 0)
node.opacity = 0.5
material.diffuse.contents = UIColor.blue

SCNTransaction.commit()
```

**Disable implicit animations** (for instant changes):

```swift
SCNTransaction.begin()
SCNTransaction.disableActions = true
node.position = newPosition
SCNTransaction.commit()
```

### Explicit Animation (CAAnimation)

```swift
// Continuous rotation
let spin = CABasicAnimation(keyPath: "rotation")
spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
spin.duration = 2
spin.repeatCount = .infinity
node.addAnimation(spin, forKey: "spin")

// Keyframe animation
let bounce = CAKeyframeAnimation(keyPath: "position.y")
bounce.values = [0, 3, 0.5, 2, 0]
bounce.keyTimes = [0, 0.3, 0.5, 0.7, 1.0]
bounce.duration = 1.5
node.addAnimation(bounce, forKey: "bounce")

// Remove
node.removeAnimation(forKey: "spin")
node.removeAnimation(forKey: "spin", blendOutDuration: 0.3) // Smooth removal
```

### Loading Animations from Files

```swift
let animScene = SCNScene(named: "walk.dae")!
let animNode = animScene.rootNode.childNode(withName: "mixamorig:Hips", recursively: true)!
let animPlayer = animNode.animationPlayer(forKey: nil)!

characterNode.addAnimationPlayer(animPlayer, forKey: "walk")
animPlayer.play()

// Blend between animations
walkPlayer.blendFactor = 0.5
runPlayer.blendFactor = 0.5
```

### SCNAnimation (Modern API)

```swift
let animation = SCNAnimation(contentsOf: animationURL)
animation.isRemovedOnCompletion = false
animation.blendInDuration = 0.3
animation.blendOutDuration = 0.3
animation.isAppliedOnCompletion = true

let player = SCNAnimationPlayer(animation: animation)
node.addAnimationPlayer(player, forKey: "idle")
player.play()
player.stop(withBlendOutDuration: 0.5)
player.paused = true
player.speed = 1.5
```

---

## Physics

> **RealityKit:** `SCNPhysicsBody` becomes `PhysicsBodyComponent` + `CollisionComponent`. Bitmasks become `CollisionGroup`/`CollisionFilter`. Contact delegate becomes `scene.subscribe(to: CollisionEvents.Began.self)`.

### Physics Body Types

```swift
// Dynamic -- simulation controls position and rotation
node.physicsBody = SCNPhysicsBody(type: .dynamic,
    shape: SCNPhysicsShape(geometry: node.geometry!, options: nil))

// Static -- immovable collision surface (walls, floors)
ground.physicsBody = SCNPhysicsBody(type: .static, shape: nil)

// Kinematic -- code controls position, participates in collisions
platform.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
```

### Body Properties

```swift
let body = node.physicsBody!
body.mass = 1.0                    // kg
body.friction = 0.5                // 0-1
body.restitution = 0.3             // Bounciness 0-1
body.damping = 0.1                 // Linear drag
body.angularDamping = 0.1          // Angular drag
body.isAffectedByGravity = true
body.allowsResting = true          // Sleep when still (performance)
body.continuousCollisionDetectionThreshold = 0.1 // For fast-moving objects
```

### Physics Shapes

```swift
// From geometry (most accurate, slowest)
let shape = SCNPhysicsShape(geometry: mesh, options: [
    .type: SCNPhysicsShape.ShapeType.convexHull  // or .concavePolyhedron (static only)
])

// Compound shapes
let compound = SCNPhysicsShape(shapes: [boxShape, sphereShape],
    transforms: [NSValue(scnMatrix4: t1), NSValue(scnMatrix4: t2)])

// Simplified shapes for performance
let bbox = SCNPhysicsShape(geometry: SCNBox(width: 1, height: 2, length: 1, chamferRadius: 0), options: nil)
```

### Collision Categories and Contact Detection

```swift
struct PhysicsCategory {
    static let player:     Int = 1 << 0
    static let enemy:      Int = 1 << 1
    static let projectile: Int = 1 << 2
    static let wall:       Int = 1 << 3
}

playerNode.physicsBody?.categoryBitMask = PhysicsCategory.player
playerNode.physicsBody?.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.enemy
playerNode.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.projectile
```

**Always set all three masks explicitly.** Default values cause unexpected collisions.

### Contact Delegate

```swift
class GameController: NSObject, SCNPhysicsContactDelegate {
    func setupPhysics(scene: SCNScene) {
        scene.physicsWorld.contactDelegate = self
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let nodeA = contact.nodeA
        let nodeB = contact.nodeB
        let contactPoint = contact.contactPoint
        let contactNormal = contact.contactNormal
        let penetrationDistance = contact.penetrationDistance
        // Handle collision
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didUpdate contact: SCNPhysicsContact) {
        // Ongoing contact
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        // Contact ended
    }
}
```

### Applying Forces

```swift
node.physicsBody?.applyForce(SCNVector3(0, 10, 0), asImpulse: true)   // Instant impulse
node.physicsBody?.applyForce(SCNVector3(0, 10, 0), asImpulse: false)  // Continuous force
node.physicsBody?.applyTorque(SCNVector4(0, 1, 0, 5), asImpulse: true) // Spin
node.physicsBody?.velocity = SCNVector3(0, 5, 0)                       // Direct velocity
node.physicsBody?.angularVelocity = SCNVector4(0, 1, 0, 3)
```

### Physics Joints

| Joint | Purpose | Example |
|---|---|---|
| `SCNPhysicsHingeJoint` | Single-axis rotation | Door, hinge |
| `SCNPhysicsBallSocketJoint` | Free rotation around point | Pendulum, ragdoll |
| `SCNPhysicsSliderJoint` | Linear movement along axis | Drawer, piston |
| `SCNPhysicsConeTwistJoint` | Limited rotation cone | Ragdoll limb |

```swift
let hinge = SCNPhysicsHingeJoint(
    body: doorBody, axis: SCNVector3(0, 1, 0), anchor: SCNVector3(-0.5, 0, 0))
scene.physicsWorld.addBehavior(hinge)
```

### Ray Casting

```swift
let results = scene.physicsWorld.rayTestWithSegment(
    from: SCNVector3(0, 10, 0),
    to: SCNVector3(0, -10, 0),
    options: [
        .searchMode: SCNPhysicsWorld.TestSearchMode.closest,
        .collisionBitMask: PhysicsCategory.wall
    ]
)
if let hit = results.first {
    let hitPoint = hit.worldCoordinates
    let hitNormal = hit.worldNormal
}
```

---

## Particle Systems

### SCNParticleSystem

```swift
let particles = SCNParticleSystem()
particles.birthRate = 100                  // Particles per second
particles.particleLifeSpan = 2.0          // Seconds
particles.particleLifeSpanVariation = 0.5
particles.particleSize = 0.1
particles.particleSizeVariation = 0.05

// Appearance
particles.particleColor = .white
particles.particleColorVariation = SCNVector4(0.5, 0.5, 0.5, 0)
particles.particleImage = UIImage(named: "spark")
particles.blendMode = .additive            // .alpha, .additive, .multiply, .screen

// Motion
particles.emittingDirection = SCNVector3(0, 1, 0)
particles.spreadingAngle = 45
particles.particleVelocity = 5.0
particles.particleVelocityVariation = 2.0
particles.acceleration = SCNVector3(0, -9.8, 0) // Gravity
particles.particleAngularVelocity = 90     // Spin (degrees/sec)

// Emitter shape
particles.emitterShape = SCNSphere(radius: 0.5)
particles.birthLocation = .surface          // .volume, .surface, .vertex

// Lifecycle
particles.isAffectedByGravity = false
particles.isAffectedByPhysicsFields = true
particles.loops = true
particles.warmupDuration = 2.0             // Pre-simulate on creation

// Size over lifetime
particles.particleSizeVariation = 0.05
particles.propertyControllers = [
    .size: SCNParticlePropertyController(animation: sizeAnimation)
]

let particleNode = SCNNode()
particleNode.addParticleSystem(particles)
scene.rootNode.addChildNode(particleNode)
```

### Loading from File

Particle systems can be designed in Xcode's particle editor and loaded:

```swift
let particles = SCNParticleSystem(named: "Fire", inDirectory: "Particles")!
node.addParticleSystem(particles)
```

### Property Controllers (Animate Over Lifetime)

```swift
// Size grows then shrinks
let sizeAnim = CAKeyframeAnimation()
sizeAnim.values = [0.0, 1.0, 0.0]
sizeAnim.keyTimes = [0, 0.5, 1.0]
sizeAnim.duration = 1.0

let controller = SCNParticlePropertyController(animation: sizeAnim)
controller.inputMode = .overLife
particles.propertyControllers = [.size: controller]
```

### Common Particle Recipes

**Fire:**

```swift
let fire = SCNParticleSystem()
fire.birthRate = 300
fire.particleLifeSpan = 0.8
fire.particleSize = 0.15
fire.particleColor = .orange
fire.particleColorVariation = SCNVector4(0.3, 0.2, 0, 0)
fire.blendMode = .additive
fire.emittingDirection = SCNVector3(0, 1, 0)
fire.spreadingAngle = 15
fire.particleVelocity = 2
```

**Snow:**

```swift
let snow = SCNParticleSystem()
snow.birthRate = 50
snow.particleLifeSpan = 10
snow.particleSize = 0.02
snow.particleColor = .white
snow.emitterShape = SCNPlane(width: 20, height: 20)
snow.birthLocation = .surface
snow.acceleration = SCNVector3(0, -0.5, 0)
snow.particleVelocity = 0.1
snow.spreadingAngle = 180
```

---

## Model Loading

### From Bundle

```swift
let scene = SCNScene(named: "model.usdz")!
let modelNode = scene.rootNode.childNode(withName: "ModelRoot", recursively: true)!
```

### From URL

```swift
let scene = try SCNScene(url: modelURL, options: [
    .checkConsistency: true,
    .convertToYUp: true,
    .flattenScene: false,       // true to merge geometry
    .createNormalsIfAbsent: true
])
```

### Via Model I/O

```swift
import ModelIO
import SceneKit.ModelIO

let asset = MDLAsset(url: modelURL)
asset.loadTextures()
let scene = SCNScene(mdlAsset: asset)
```

### SCNSceneSource (Selective Loading)

```swift
let source = SCNSceneSource(url: modelURL, options: nil)!

// List available items
let ids = source.identifiersOfEntries(withClass: SCNNode.self)

// Load specific node
let node = source.entryWithIdentifier("character", withClass: SCNNode.self)!

// Load animation only
let animation = source.entryWithIdentifier("walk", withClass: CAAnimation.self)
```

### Format Conversion (CLI)

```bash
# Convert .scn to .usdz
xcrun scntool --convert model.scn --format usdz --output model.usdz

# Convert .dae to .usdz
xcrun scntool --convert model.dae --format usdz --output model.usdz
```

---

## Constraints

> **RealityKit:** No constraint system. Implement equivalent behavior in a `System` update loop. `SCNLookAtConstraint` maps to `entity.look(at:from:relativeTo:)`.

| Constraint | Purpose |
|---|---|
| `SCNLookAtConstraint` | Node always faces a target node |
| `SCNBillboardConstraint` | Node always faces camera |
| `SCNDistanceConstraint` | Maintains min/max distance from target |
| `SCNReplicatorConstraint` | Copies transform of target |
| `SCNAccelerationConstraint` | Smooths transform changes (damping) |
| `SCNSliderConstraint` | Locks movement to an axis |
| `SCNIKConstraint` | Inverse kinematics chain |

```swift
// Look-at
let lookAt = SCNLookAtConstraint(target: targetNode)
lookAt.isGimbalLockEnabled = true    // Prevent roll
lookAt.influenceFactor = 0.8         // Partial constraint (smooth follow)
node.constraints = [lookAt]

// Billboard (always face camera)
let billboard = SCNBillboardConstraint()
billboard.freeAxes = .Y              // Only rotate around Y axis
labelNode.constraints = [billboard]

// Distance clamp
let dist = SCNDistanceConstraint(target: playerNode)
dist.minimumDistance = 3
dist.maximumDistance = 10
cameraNode.constraints = [dist]
```

---

## Hit Testing and Interaction

### View-Level Hit Testing

```swift
let results = sceneView.hitTest(screenPoint, options: [
    .searchMode: SCNHitTestSearchMode.closest.rawValue,
    .boundingBoxOnly: false,           // true for faster, less accurate
    .categoryBitMask: 1,              // Only test specific categories
    .ignoreHiddenNodes: true,
    .rootNode: specificSubtree,        // Limit search scope
    .ignoreChildNodes: false
])

if let hit = results.first {
    hit.node                           // The node that was hit
    hit.worldCoordinates               // Hit point in world space
    hit.localCoordinates               // Hit point in node's local space
    hit.worldNormal                    // Surface normal at hit point
    hit.geometryIndex                  // Which geometry element
    hit.faceIndex                      // Which triangle
    hit.textureCoordinates(withMappingChannel: 0) // UV at hit point
}
```

---

## Renderer Delegate (Per-Frame Updates)

```swift
class GameController: NSObject, SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Game logic, input processing (called before physics)
    }

    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        // Post-physics adjustments
    }

    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        // Pre-render setup (update uniforms, etc.)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        // Post-render (capture framebuffer, etc.)
    }
}

sceneView.delegate = gameController
```

---

## Performance

### Level of Detail (LOD)

```swift
let highPoly = SCNSphere(radius: 1)
highPoly.segmentCount = 48

let lowPoly = SCNSphere(radius: 1)
lowPoly.segmentCount = 12

highPoly.levelsOfDetail = [
    SCNLevelOfDetail(geometry: lowPoly, screenSpaceRadius: 50),  // Switch when smaller than 50pt on screen
    SCNLevelOfDetail(geometry: nil, screenSpaceRadius: 10)       // Cull when smaller than 10pt
]
```

### Geometry Flattening

```swift
// Merge all child geometry into one draw call
let flattened = parentNode.flattenedClone()

// Clone for instancing (shares geometry data)
let instance = originalNode.clone()
instance.position = SCNVector3(5, 0, 0)
```

### Draw Call Reduction

- **Flatten** similar geometry with `flattenedClone()` -- reduces draw calls
- **Share materials** across nodes when possible -- enables batching
- **Use LOD** to reduce triangle count at distance
- **Limit shadow-casting lights** to 1-2 per scene
- **Set `castsShadow = false`** on nodes that do not need shadows
- **Use `categoryBitMask`** on lights to limit which nodes they affect
- **Reduce `shadowSampleCount`** and `shadowMapSize` for performance
- **Enable `allowsResting`** on physics bodies to sleep still objects

### Occlusion Culling

SceneKit performs frustum culling automatically. For large scenes with dense occluders, additional strategies:

```swift
// Manual visibility toggle based on distance or game logic
node.isHidden = distanceToCamera > 50

// Rendering order for transparency sorting
transparentNode.renderingOrder = 100  // Render after opaque
```

### Performance Monitoring

```swift
sceneView.showsStatistics = true

// Programmatic access
if let stats = sceneView.statistics {
    // Frame time, draw calls, triangle count, etc.
}
```

**Target metrics:**

| Metric | Target |
|---|---|
| Frame rate | 60 fps (16.67ms per frame) |
| Draw calls | < 100 |
| Triangle count | < 500K for iPhone, < 1M for iPad |
| Node count | Flatten when > 50 similar |

---

## Metal Custom Shaders

### Shader Modifiers (Quick Customization)

Inject Metal shader snippets at specific pipeline entry points:

```swift
// Entry points: .geometry, .surface, .lightingModel, .fragment

// Vertex displacement (geometry entry point)
material.shaderModifiers = [
    .geometry: """
    float wave = sin(_geometry.position.x * 10.0 + u_time * 3.0) * 0.1;
    _geometry.position.y += wave;
    """
]

// Custom surface color (surface entry point)
material.shaderModifiers = [
    .surface: """
    float stripe = step(0.5, fract(_surface.diffuseTexcoord.y * 20.0));
    _surface.diffuse = mix(float4(1,0,0,1), float4(0,0,1,1), stripe);
    """
]

// Custom fragment output
material.shaderModifiers = [
    .fragment: """
    float scanline = step(0.5, fract(_output.color.r * 50.0));
    _output.color.rgb *= 0.5 + 0.5 * scanline;
    """
]
```

**Built-in variables in shader modifiers:**

| Entry Point | Available Variables |
|---|---|
| `.geometry` | `_geometry.position`, `_geometry.normal`, `_geometry.texcoords[N]`, `u_time` |
| `.surface` | `_surface.diffuse`, `_surface.normal`, `_surface.diffuseTexcoord`, `_surface.position`, `u_time` |
| `.lightingModel` | `_lightingContribution.diffuse`, `_lightingContribution.specular`, `_light.direction`, `_light.intensity` |
| `.fragment` | `_output.color`, `u_time` |

### Passing Custom Uniforms

```swift
// Set a custom value accessible in shader modifiers
material.setValue(Float(1.5), forKey: "intensity")
material.setValue(SCNVector3(1, 0, 0), forKey: "highlightDirection")

// In shader modifier:
// uniform float intensity;
// uniform float3 highlightDirection;
```

### SCNProgram (Full Custom Shader)

Replace the entire rendering pipeline for a material:

```swift
let program = SCNProgram()
program.vertexFunctionName = "myVertexShader"
program.fragmentFunctionName = "myFragmentShader"

// Map SceneKit semantics to shader inputs
program.handleBinding(ofBufferNamed: "uniforms", frequency: .perFrame) { stream, node, shadable, renderer in
    // Provide uniform buffer data
}

material.program = program
```

**Metal shader for SCNProgram:**

```metal
#include <metal_stdlib>
#include <SceneKit/scn_metal>
using namespace metal;

struct VertexInput {
    float3 position [[attribute(SCNVertexSemanticPosition)]];
    float3 normal   [[attribute(SCNVertexSemanticNormal)]];
    float2 texcoord [[attribute(SCNVertexSemanticTexcoord0)]];
};

struct VertexOutput {
    float4 position [[position]];
    float3 normal;
    float2 texcoord;
};

vertex VertexOutput myVertexShader(VertexInput in [[stage_in]],
                                    constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                                    constant SCNNodeBuffer& scn_node [[buffer(1)]]) {
    VertexOutput out;
    out.position = scn_frame.viewProjectionTransform * scn_node.modelTransform * float4(in.position, 1.0);
    out.normal = (scn_node.normalTransform * float4(in.normal, 0.0)).xyz;
    out.texcoord = in.texcoord;
    return out;
}

fragment float4 myFragmentShader(VertexOutput in [[stage_in]]) {
    float3 lightDir = normalize(float3(0.5, 1.0, 0.5));
    float diffuse = max(dot(normalize(in.normal), lightDir), 0.0);
    return float4(float3(diffuse), 1.0);
}
```

### SCNTechnique (Multi-Pass Post-Processing)

Define multi-pass rendering pipelines via a technique definition dictionary:

```swift
let techniqueDef: [String: Any] = [
    "passes": [
        "outline_pass": [
            "draw": "DRAW_SCENE",
            "program": "outlineProgram",
            "metalVertexShader": "outlineVertex",
            "metalFragmentShader": "outlineFragment",
            "inputs": [
                "colorSampler": "COLOR",
                "depthSampler": "DEPTH"
            ],
            "outputs": [
                "color": "COLOR"
            ]
        ]
    ],
    "sequence": ["outline_pass"],
    "symbols": [
        "outlineWidth": ["type": "float", "value": 2.0]
    ]
]

if let technique = SCNTechnique(dictionary: techniqueDef) {
    sceneView.technique = technique
}
```

**Common technique uses:**

- Edge detection / outline rendering
- Bloom / glow post-processing
- Custom deferred shading
- Screen-space effects (blur, distortion)
- Multi-pass shadow techniques

### Technique with Metal Shaders

```swift
// Pass custom values to technique shaders
technique?.setValue(NSNumber(value: 2.0), forKey: "outlineWidth")
technique?.setValue(SCNVector3(1, 0, 0), forKey: "outlineColor")
```

**Metal shader for technique pass:**

```metal
fragment float4 outlineFragment(VertexOutput in [[stage_in]],
                                 texture2d<float> colorTexture [[texture(0)]],
                                 texture2d<float> depthTexture [[texture(1)]],
                                 constant float& outlineWidth [[buffer(0)]]) {
    constexpr sampler s(filter::linear);
    float4 color = colorTexture.sample(s, in.texcoord);

    // Edge detection using depth discontinuities
    float depth = depthTexture.sample(s, in.texcoord).r;
    float depthRight = depthTexture.sample(s, in.texcoord + float2(outlineWidth / 1024.0, 0)).r;
    float depthUp = depthTexture.sample(s, in.texcoord + float2(0, outlineWidth / 1024.0)).r;

    float edge = abs(depth - depthRight) + abs(depth - depthUp);
    if (edge > 0.001) {
        color = float4(0, 0, 0, 1); // Black outline
    }
    return color;
}
```

---

## Scene Serialization

### Saving Scenes

```swift
// Write to file
let success = scene.write(to: fileURL, options: nil, delegate: nil, progressHandler: nil)

// With options
scene.write(to: fileURL, options: [
    "SCNSceneExportDestinationURL": destinationFolder
], delegate: nil) { totalProgress, error, stop in
    print("Export progress: \(totalProgress)")
}
```

---

## Common Patterns

### Orbit Camera Controller

```swift
class OrbitCameraController {
    let cameraNode: SCNNode
    var distance: Float = 10
    var longitude: Float = 0
    var latitude: Float = 30

    func updateCamera() {
        let latRad = latitude * .pi / 180
        let lonRad = longitude * .pi / 180
        let x = distance * cos(latRad) * sin(lonRad)
        let y = distance * sin(latRad)
        let z = distance * cos(latRad) * cos(lonRad)
        cameraNode.position = SCNVector3(x, y, z)
        cameraNode.look(at: SCNVector3.zero)
    }
}
```

### Day/Night Cycle

```swift
func updateLighting(timeOfDay: Float) { // 0-24
    let angle = (timeOfDay / 24.0) * Float.pi * 2 - Float.pi / 2
    sunNode.eulerAngles.x = -angle

    let intensity: CGFloat = max(0, CGFloat(sin(angle))) * 1000
    sunNode.light?.intensity = intensity
    sunNode.light?.color = timeOfDay > 6 && timeOfDay < 18
        ? UIColor.white
        : UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
}
```

### Scene Snapshot / Thumbnail

```swift
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
let image = renderer.snapshot(atTime: 0, with: CGSize(width: 512, height: 512), antialiasingMode: .multisampling4X)
```
