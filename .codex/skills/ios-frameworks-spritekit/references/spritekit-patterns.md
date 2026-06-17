# SpriteKit -- Patterns & API Reference

Complete reference for SpriteKit scene lifecycle, node hierarchy, physics, actions, texture management, and SwiftUI integration. All examples target iOS 26+.

---

## Scene Lifecycle

### Creation and Presentation

```swift
class GameScene: SKScene {
    override func didMove(to view: SKView) {
        // Called once when scene is presented
        // Setup nodes, physics, camera here
    }

    override func willMove(from view: SKView) {
        // Cleanup before scene is removed
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Called when scene size changes (rotation, resize)
    }
}
```

### Game Loop Order

Each frame executes in this order:

1. `update(_ currentTime: TimeInterval)` -- per-frame game logic
2. `didEvaluateActions()` -- after all SKActions execute
3. `didSimulatePhysics()` -- after physics simulation step
4. `didApplyConstraints()` -- after constraint evaluation
5. `didFinishUpdate()` -- final callback before rendering

```swift
class GameScene: SKScene {
    private var lastUpdateTime: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        // Clamp dt to prevent spiral of death when returning from background
        let clampedDt = min(dt, 1.0 / 30.0)

        // Use clampedDt for frame-rate-independent movement
        player.position.x += playerSpeed * clampedDt
    }

    override func didSimulatePhysics() {
        // Clamp player to screen bounds after physics resolves
        player.position.x = player.position.x.clamped(to: 0...size.width)
    }
}
```

### Scale Modes

| Mode | Behavior | Use Case |
|---|---|---|
| `.aspectFill` | Scales to fill view, may crop edges | Games (default choice) |
| `.aspectFit` | Scales to fit, may letterbox | UI scenes, puzzles |
| `.resizeFill` | Stretches to fill exactly | Utility scenes, backgrounds |
| `.fill` | Scene size matches view size | Adaptive layouts |

```swift
class GameScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
    }
}
```

### Scene Transitions

```swift
let nextScene = LevelScene(size: size)
nextScene.scaleMode = scaleMode

let transition = SKTransition.fade(withDuration: 0.5)
view?.presentScene(nextScene, transition: transition)
```

Transition types: `.crossFade`, `.fade(with:)`, `.flipHorizontal`, `.doorway`, `.push(with:)`, `.reveal(with:)`, `.moveIn(with:)`

---

## Node Hierarchy

### SKNode (Base)

All nodes inherit from `SKNode`. Key properties:

```swift
node.position = CGPoint(x: 100, y: 200)   // In parent's coordinate space
node.zPosition = 10                         // Draw order (higher = front)
node.zRotation = .pi / 4                    // Radians, counterclockwise
node.xScale = 1.0                           // Horizontal scale
node.yScale = 1.0                           // Vertical scale
node.alpha = 0.8                            // Opacity
node.isHidden = false
node.isPaused = false                       // Pauses actions and physics
node.name = "player"                        // For lookup
```

### SKSpriteNode

The workhorse node for textured content.

```swift
// From image asset
let sprite = SKSpriteNode(imageNamed: "hero")
sprite.size = CGSize(width: 64, height: 64)
sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)  // Default: center

// From texture atlas
let atlas = SKTextureAtlas(named: "Characters")
let texture = atlas.textureNamed("hero_idle_01")
let sprite = SKSpriteNode(texture: texture)

// Colored rectangle (no image)
let block = SKSpriteNode(color: .red, size: CGSize(width: 50, height: 50))
```

### SKShapeNode

Vector path rendering. Expensive to render -- avoid for large quantities.

```swift
// Circle
let circle = SKShapeNode(circleOfRadius: 30)
circle.fillColor = .blue
circle.strokeColor = .white
circle.lineWidth = 2

// Rectangle
let rect = SKShapeNode(rectOf: CGSize(width: 100, height: 50), cornerRadius: 8)

// Custom path
let path = CGMutablePath()
path.move(to: .zero)
path.addLine(to: CGPoint(x: 100, y: 0))
path.addLine(to: CGPoint(x: 50, y: 80))
path.closeSubpath()
let triangle = SKShapeNode(path: path)

// Performance tip: convert to texture for static shapes
if let texture = view.texture(from: circle) {
    let sprite = SKSpriteNode(texture: texture)
    // Use sprite instead of circle
}
```

### SKLabelNode

```swift
let label = SKLabelNode(text: "Score: 0")
label.fontName = "AvenirNext-Bold"
label.fontSize = 24
label.fontColor = .white
label.horizontalAlignmentMode = .left
label.verticalAlignmentMode = .top
label.numberOfLines = 0  // Multiline

// Attributed text
let attrString = NSAttributedString(
    string: "Game Over",
    attributes: [
        .font: UIFont.systemFont(ofSize: 48, weight: .bold),
        .foregroundColor: UIColor.red
    ]
)
label.attributedText = attrString
```

### SKEmitterNode (Particles)

```swift
// From .sks file (designed in Xcode Particle Editor)
guard let emitter = SKEmitterNode(fileNamed: "Fire") else { return }
emitter.position = CGPoint(x: 200, y: 100)
emitter.targetNode = self  // Particles stay in scene space, not emitter space
addChild(emitter)

// Programmatic emitter
let sparks = SKEmitterNode()
sparks.particleTexture = SKTexture(imageNamed: "spark")
sparks.particleBirthRate = 200
sparks.particleLifetime = 1.0
sparks.particleSpeed = 150
sparks.particleSpeedRange = 50
sparks.emissionAngleRange = .pi * 2
sparks.particleScale = 0.3
sparks.particleScaleRange = 0.2
sparks.particleAlphaSpeed = -1.0  // Fade out over lifetime
sparks.particleColorBlendFactor = 1.0
sparks.particleColor = .yellow
```

### One-Shot Particle Pattern

```swift
func spawnExplosion(at position: CGPoint) {
    guard let explosion = SKEmitterNode(fileNamed: "Explosion") else { return }
    explosion.position = position
    explosion.zPosition = 100
    addChild(explosion)

    // Auto-remove after particles finish
    let wait = SKAction.wait(forDuration: TimeInterval(explosion.particleLifetime + explosion.particleLifetimeRange))
    let remove = SKAction.removeFromParent()
    explosion.run(.sequence([wait, remove]))
}
```

### SKEffectNode

Applies Core Image filters to child nodes.

```swift
let effectNode = SKEffectNode()
effectNode.shouldEnableEffects = true
effectNode.shouldRasterize = true  // Cache result for performance
effectNode.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 10])
effectNode.addChild(backgroundSprite)
addChild(effectNode)
```

### SKCropNode

Masks child content.

```swift
let cropNode = SKCropNode()

// Mask shape -- only white/opaque areas show through
let mask = SKSpriteNode(imageNamed: "circle_mask")
cropNode.maskNode = mask

// Content to be masked
let content = SKSpriteNode(imageNamed: "photo")
cropNode.addChild(content)
addChild(cropNode)
```

### Node Lookup

```swift
// By name
if let player = childNode(withName: "player") as? SKSpriteNode { ... }

// Recursive search
enumerateChildNodes(withName: "//enemy") { node, stop in
    // "//" searches all descendants
}

// Pattern matching
enumerateChildNodes(withName: "bullet_*") { node, _ in
    // Matches bullet_1, bullet_2, etc.
}
```

---

## Physics

### SKPhysicsBody

```swift
// Dynamic body (affected by forces)
let body = SKPhysicsBody(circleOfRadius: 30)
body.mass = 1.0
body.friction = 0.3
body.restitution = 0.5        // Bounciness (0-1)
body.linearDamping = 0.1      // Air resistance
body.angularDamping = 0.2
body.allowsRotation = true
body.affectedByGravity = true
sprite.physicsBody = body

// Static body (immovable)
let ground = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 20))
ground.isDynamic = false
groundNode.physicsBody = ground

// Edge-based body (thin boundary, always static)
let border = SKPhysicsBody(edgeLoopFrom: frame)
self.physicsBody = border
```

Body shapes:
- `circleOfRadius:` -- cheapest, best for round objects
- `rectangleOf:` -- good for boxes
- `polygonFrom:` -- convex polygon from CGPath (max 12 vertices)
- `texture:size:` -- pixel-perfect from alpha channel (expensive, avoid in bulk)
- `edgeFrom:` / `edgeLoopFrom:` -- thin boundaries, volume-less

### Contact Detection

```swift
struct PhysicsCategory {
    static let none:       UInt32 = 0
    static let player:     UInt32 = 1 << 0
    static let enemy:      UInt32 = 1 << 1
    static let projectile: UInt32 = 1 << 2
    static let powerup:    UInt32 = 1 << 3
    static let wall:       UInt32 = 1 << 4
}

// Player setup
player.physicsBody?.categoryBitMask = PhysicsCategory.player
player.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.powerup
player.physicsBody?.collisionBitMask = PhysicsCategory.wall

// Implement delegate
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let sorted = [contact.bodyA, contact.bodyB].sorted { $0.categoryBitMask < $1.categoryBitMask }
        guard let first = sorted.first, let second = sorted.last else { return }

        switch (first.categoryBitMask, second.categoryBitMask) {
        case (PhysicsCategory.player, PhysicsCategory.enemy):
            handlePlayerEnemyContact(player: first.node, enemy: second.node)
        case (PhysicsCategory.player, PhysicsCategory.powerup):
            handlePowerupPickup(powerup: second.node)
        default:
            break
        }
    }
}
```

**Key distinction**: `collisionBitMask` controls physical bounce/blocking. `contactTestBitMask` controls whether `didBegin`/`didEnd` callbacks fire. They are independent.

### Forces and Impulses

```swift
// Force -- continuous, applied over time (use in update loop)
body.applyForce(CGVector(dx: 0, dy: 100))

// Impulse -- instantaneous velocity change (use for jumps, explosions)
body.applyImpulse(CGVector(dx: 0, dy: 300))

// Angular
body.applyTorque(5.0)           // Continuous rotation force
body.applyAngularImpulse(2.0)   // Instant spin

// Targeted force at a point
body.applyForce(CGVector(dx: 100, dy: 0), at: CGPoint(x: 0, y: 20))
```

### Joints

```swift
// Pin joint (pivot)
let pin = SKPhysicsJointPin.joint(
    withBodyA: nodeA.physicsBody!,
    bodyB: nodeB.physicsBody!,
    anchor: nodeA.position
)
physicsWorld.add(pin)

// Spring joint
let spring = SKPhysicsJointSpring.joint(
    withBodyA: nodeA.physicsBody!,
    bodyB: nodeB.physicsBody!,
    anchorA: nodeA.position,
    anchorB: nodeB.position
)
spring.frequency = 1.0
spring.damping = 0.2
physicsWorld.add(spring)

// Fixed joint (rigid connection)
let fixed = SKPhysicsJointFixed.joint(
    withBodyA: nodeA.physicsBody!,
    bodyB: nodeB.physicsBody!,
    anchor: nodeA.position
)
physicsWorld.add(fixed)
```

Other joint types: `SKPhysicsJointSliding` (piston), `SKPhysicsJointLimit` (rope).

### Ray Casting and Point Queries

```swift
// Find body at a point (e.g. tap location)
if let body = physicsWorld.body(at: tapLocation) {
    print("Tapped: \(body.node?.name ?? "unknown")")
}

// Find body in a rectangle
if let body = physicsWorld.body(in: selectionRect) {
    // First body found in rect
}

// Ray cast -- enumerate all bodies along a line (line of sight, targeting)
physicsWorld.enumerateBodies(alongRayStart: playerPosition, end: targetPosition) { body, point, normal, stop in
    if body.categoryBitMask & PhysicsCategory.wall != 0 {
        // Wall blocks line of sight
        stop.pointee = true  // Stop enumerating
    }
}
```

### Constraints

```swift
// Orient toward another node (e.g. turret tracking enemy)
let orient = SKConstraint.orient(to: targetNode, offset: SKRange(constantValue: 0))

// Keep node within X bounds
let xBounds = SKConstraint.positionX(SKRange(lowerLimit: 0, upperLimit: 400))

// Keep node within Y bounds
let yBounds = SKConstraint.positionY(SKRange(lowerLimit: 50, upperLimit: 750))

// Stay within distance range of another node
let tether = SKConstraint.distance(SKRange(lowerLimit: 50, upperLimit: 200), to: anchorNode)

// Constrain rotation
let rotLimit = SKConstraint.zRotation(SKRange(lowerLimit: -.pi / 4, upperLimit: .pi / 4))

// Apply multiple constraints (processed in order)
node.constraints = [orient, xBounds, yBounds]

// SKRange constructors
SKRange(constantValue: 100)               // Exactly 100
SKRange(lowerLimit: 50, upperLimit: 200)  // 50...200
SKRange(value: 100, variance: 20)         // 80...120
```

---

## Actions

### Core Actions

```swift
// Movement
SKAction.move(to: CGPoint(x: 200, y: 300), duration: 1.0)
SKAction.move(by: CGVector(dx: 100, dy: 0), duration: 0.5)
SKAction.follow(path, asOffset: false, orientToPath: true, duration: 3.0)

// Scaling
SKAction.scale(to: 2.0, duration: 0.3)
SKAction.scale(by: 0.5, duration: 0.3)

// Rotation
SKAction.rotate(byAngle: .pi * 2, duration: 1.0)
SKAction.rotate(toAngle: 0, duration: 0.5, shortestUnitArc: true)

// Fade
SKAction.fadeIn(withDuration: 0.3)
SKAction.fadeOut(withDuration: 0.3)
SKAction.fadeAlpha(to: 0.5, duration: 0.3)

// Color
SKAction.colorize(with: .red, colorBlendFactor: 1.0, duration: 0.2)

// Resize
SKAction.resize(toWidth: 100, height: 100, duration: 0.5)

// Speed
SKAction.speed(to: 2.0, duration: 0.3)

// Remove
SKAction.removeFromParent()

// Sound
SKAction.playSoundFileNamed("hit.wav", waitForCompletion: false)

// Wait
SKAction.wait(forDuration: 1.0)
SKAction.wait(forDuration: 1.0, withRange: 0.5)  // Random 0.75-1.25s
```

### Composition

```swift
// Sequential
let sequence = SKAction.sequence([
    .move(to: target, duration: 0.5),
    .wait(forDuration: 0.2),
    .fadeOut(withDuration: 0.3),
    .removeFromParent()
])

// Parallel
let group = SKAction.group([
    .move(to: target, duration: 0.5),
    .scale(to: 2.0, duration: 0.5),
    .fadeOut(withDuration: 0.5)
])

// Repeat
let pulse = SKAction.sequence([
    .scale(to: 1.2, duration: 0.3),
    .scale(to: 1.0, duration: 0.3)
])
node.run(.repeatForever(pulse))
node.run(.repeat(pulse, count: 3))

// Run block
let update = SKAction.run { [weak self] in
    self?.score += 10
    self?.updateScoreLabel()
}
node.run(.sequence([.wait(forDuration: 1.0), update]))
```

### Sprite Sheet Animation

```swift
let atlas = SKTextureAtlas(named: "PlayerRun")
let textures = (1...8).map { atlas.textureNamed("run_\($0)") }

let animate = SKAction.animate(with: textures, timePerFrame: 0.1)
player.run(.repeatForever(animate), withKey: "running")

// Stop a named action
player.removeAction(forKey: "running")
```

### Timing Functions

```swift
let action = SKAction.move(to: target, duration: 1.0)
action.timingMode = .easeInEaseOut  // Also: .linear, .easeIn, .easeOut

// Custom timing with SKAction.customAction
let custom = SKAction.customAction(withDuration: 2.0) { node, elapsed in
    let fraction = elapsed / 2.0
    node.alpha = 1.0 - fraction
    node.xScale = 1.0 + fraction * 0.5
}
```

---

## Texture Atlases

### Setup

Add a `.atlas` folder to your asset catalog or project. Xcode compiles it into an optimized atlas at build time.

```
Textures.atlas/
    hero_idle_01.png
    hero_idle_02.png
    hero_run_01.png
    hero_run_02.png
    enemy_01.png
```

### Loading

```swift
// Load atlas
let atlas = SKTextureAtlas(named: "Textures")

// Preload for smooth gameplay
SKTextureAtlas.preloadTextureAtlases([atlas]) {
    // Atlases are now in GPU memory
    self.startGame()
}

// Access individual textures
let texture = atlas.textureNamed("hero_idle_01")
```

### Texture Filtering

```swift
// Pixel art -- use nearest neighbor
texture.filteringMode = .nearest

// Smooth art -- use linear (default)
texture.filteringMode = .linear
```

---

## Camera

```swift
class GameScene: SKScene {
    let cameraNode = SKCameraNode()

    override func didMove(to view: SKView) {
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    func followPlayer() {
        // Smooth follow with constraint
        let range = SKRange(constantValue: 0)
        let follow = SKConstraint.distance(range, to: player)
        cameraNode.constraints = [follow]
    }

    func zoomCamera(to scale: CGFloat) {
        let zoom = SKAction.scale(to: scale, duration: 0.3)
        cameraNode.run(zoom)
    }
}
```

### HUD Attached to Camera

Nodes added as children of the camera stay fixed on screen regardless of camera movement.

```swift
let scoreLabel = SKLabelNode(text: "0")
scoreLabel.position = CGPoint(x: -size.width / 2 + 20, y: size.height / 2 - 40)
scoreLabel.horizontalAlignmentMode = .left
cameraNode.addChild(scoreLabel)

let pauseButton = SKSpriteNode(imageNamed: "pause")
pauseButton.position = CGPoint(x: size.width / 2 - 30, y: size.height / 2 - 40)
pauseButton.name = "pauseButton"
cameraNode.addChild(pauseButton)
```

### Camera Bounds

```swift
// Constrain camera to level bounds
let levelRect = CGRect(x: 0, y: 0, width: levelWidth, height: levelHeight)
let xRange = SKRange(lowerLimit: size.width / 2, upperLimit: levelWidth - size.width / 2)
let yRange = SKRange(lowerLimit: size.height / 2, upperLimit: levelHeight - size.height / 2)
let edgeConstraint = SKConstraint.positionX(xRange, y: yRange)
cameraNode.constraints = [follow, edgeConstraint]
```

---

## Tile Maps

```swift
// Load tile set from .sks
guard let tileSet = SKTileSet(named: "Terrain") else { return }
let tileSize = CGSize(width: 32, height: 32)
let columns = 40
let rows = 30

let tileMap = SKTileMapNode(
    tileSet: tileSet,
    columns: columns,
    rows: rows,
    tileSize: tileSize
)
tileMap.enableAutomapping = true
addChild(tileMap)

// Set tiles programmatically
if let grassGroup = tileSet.tileGroups.first(where: { $0.name == "Grass" }) {
    for col in 0..<columns {
        tileMap.setTileGroup(grassGroup, forColumn: col, row: 0)
    }
}
```

### Tile Map Physics

```swift
// Add physics per-tile for collision
func addPhysicsToTileMap(_ tileMap: SKTileMapNode) {
    for col in 0..<tileMap.numberOfColumns {
        for row in 0..<tileMap.numberOfRows {
            guard tileMap.tileGroup(atColumn: col, row: row) != nil else { continue }
            let center = tileMap.centerOfTile(atColumn: col, row: row)
            let body = SKPhysicsBody(rectangleOf: tileMap.tileSize, center: center)
            body.isDynamic = false
            body.categoryBitMask = PhysicsCategory.wall
            // Aggregate or add individual nodes
        }
    }
}
```

---

## Touch Handling

```swift
class GameScene: SKScene {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check what was tapped
        let tappedNodes = nodes(at: location)
        for node in tappedNodes {
            if node.name == "pauseButton" {
                togglePause()
                return
            }
        }

        // Move player to tap
        let move = SKAction.move(to: location, duration: 0.3)
        player.run(move)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        // Drag logic
        player.position = location
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Release logic
    }
}
```

---

## SwiftUI Integration

### Basic SpriteView

```swift
struct GameView: View {
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .aspectFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
```

### With Pause and Debug Options

```swift
struct GameView: View {
    @State private var scene = GameScene(size: CGSize(width: 390, height: 844))
    @State private var isPaused = false

    var body: some View {
        ZStack {
            SpriteView(
                scene: scene,
                isPaused: isPaused,
                preferredFramesPerSecond: 60,
                debugOptions: [.showsFPS, .showsNodeCount]
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(isPaused ? "Resume" : "Pause") {
                        isPaused.toggle()
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
```

### Communicating Between SwiftUI and SKScene

Use a shared observable model -- never reach into the scene from SwiftUI body.

```swift
@Observable
class GameState {
    var score = 0
    var isGameOver = false
    var level = 1
}

class GameScene: SKScene {
    var gameState: GameState?

    func playerScored() {
        gameState?.score += 10
    }
}

struct GameView: View {
    @State private var gameState = GameState()
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .aspectFill
        return scene
    }()

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()

            if gameState.isGameOver {
                GameOverOverlay(score: gameState.score)
            }
        }
        .onAppear {
            scene.gameState = gameState
        }
    }
}
```

---

## Performance Patterns

### Measurement

```swift
override func didMove(to view: SKView) {
    view.showsFPS = true
    view.showsNodeCount = true
    view.showsDrawCount = true
    view.showsPhysics = true       // Visualize physics bodies
    view.showsFields = true        // Visualize physics fields
}
```

### Draw Call Optimization

Each unique texture in a z-position layer generates a draw call. Minimize draw calls by:

1. **Use texture atlases** -- sprites from the same atlas with the same z-position batch into one draw call
2. **Minimize z-position layers** -- group sprites at the same z-position when possible
3. **Avoid blending changes** -- keep `blendMode` consistent within a layer

### Node Pool / Object Recycling

```swift
class BulletPool {
    private var available: [SKSpriteNode] = []
    private let texture: SKTexture

    init(texture: SKTexture, initialCount: Int = 20) {
        self.texture = texture
        for _ in 0..<initialCount {
            available.append(createBullet())
        }
    }

    private func createBullet() -> SKSpriteNode {
        let bullet = SKSpriteNode(texture: texture)
        bullet.name = "bullet"
        return bullet
    }

    func spawn() -> SKSpriteNode {
        let bullet = available.isEmpty ? createBullet() : available.removeLast()
        bullet.isHidden = false
        bullet.removeAllActions()
        bullet.physicsBody?.velocity = .zero
        return bullet
    }

    func recycle(_ bullet: SKSpriteNode) {
        bullet.removeFromParent()
        bullet.isHidden = true
        available.append(bullet)
    }
}
```

### Texture Preloading

```swift
func preloadAssets(completion: @escaping () -> Void) {
    let atlases = [
        SKTextureAtlas(named: "Characters"),
        SKTextureAtlas(named: "Environment"),
        SKTextureAtlas(named: "Effects")
    ]

    SKTextureAtlas.preloadTextureAtlases(atlases) {
        completion()
    }
}
```

### Performance Rules of Thumb

| Metric | Target | Warning |
|---|---|---|
| Node count | < 500 | 1000+ causes frame drops |
| Draw calls | < 50 | Batch with atlases and z-position |
| Physics bodies | < 200 | Simplify shapes, remove off-screen |
| Particle emitters | < 10 active | Use `targetNode` and auto-remove |
| Frame rate | 60 FPS | Drop to 30 only for battery-critical apps |

### Off-Screen Culling

```swift
override func didSimulatePhysics() {
    enumerateChildNodes(withName: "bullet") { node, _ in
        if !self.frame.intersects(node.frame) {
            self.bulletPool.recycle(node as! SKSpriteNode)
        }
    }
}
```

---

## Lighting

```swift
// Light node
let light = SKLightNode()
light.categoryBitMask = 1
light.falloff = 1.0
light.ambientColor = UIColor(white: 0.3, alpha: 1.0)
light.lightColor = .white
light.shadowColor = UIColor(white: 0, alpha: 0.5)
light.position = player.position
addChild(light)

// Sprites that receive light
sprite.lightingBitMask = 1
sprite.shadowCastBitMask = 1    // Casts shadows
sprite.shadowedBitMask = 1      // Receives shadows
sprite.normalTexture = SKTexture(imageNamed: "hero_normal")  // Normal map
```

---

## Audio

```swift
// One-shot sound via action
run(SKAction.playSoundFileNamed("coin.wav", waitForCompletion: false))

// Background music with SKAudioNode (supports positional audio)
let music = SKAudioNode(fileNamed: "background.m4a")
music.autoplayLooped = true
music.isPositional = false
addChild(music)

// Control playback
music.run(SKAction.changeVolume(to: 0.5, duration: 1.0))
music.run(SKAction.pause())
music.run(SKAction.play())
```

---

## Common Game Patterns

### Spawner with Increasing Difficulty

```swift
func startSpawning() {
    let spawn = SKAction.run { [weak self] in
        self?.spawnEnemy()
    }
    let delay = SKAction.wait(forDuration: 2.0, withRange: 1.0)
    run(.repeatForever(.sequence([spawn, delay])), withKey: "spawning")
}

func increaseDifficulty() {
    removeAction(forKey: "spawning")
    let spawn = SKAction.run { [weak self] in self?.spawnEnemy() }
    let delay = SKAction.wait(forDuration: max(0.5, 2.0 - Double(level) * 0.2))
    run(.repeatForever(.sequence([spawn, delay])), withKey: "spawning")
}
```

### Parallax Scrolling

```swift
struct ParallaxLayer {
    let node: SKSpriteNode
    let speed: CGFloat
}

var parallaxLayers: [ParallaxLayer] = []

func setupParallax() {
    let speeds: [CGFloat] = [0.2, 0.5, 1.0]  // Back to front
    for (i, speed) in speeds.enumerated() {
        for j in 0...1 {
            let bg = SKSpriteNode(imageNamed: "bg_layer_\(i)")
            bg.anchorPoint = .zero
            bg.position = CGPoint(x: bg.size.width * CGFloat(j), y: 0)
            bg.zPosition = CGFloat(-10 + i)
            addChild(bg)
            parallaxLayers.append(ParallaxLayer(node: bg, speed: speed))
        }
    }
}

override func update(_ currentTime: TimeInterval) {
    for layer in parallaxLayers {
        layer.node.position.x -= layer.speed * 2
        if layer.node.position.x <= -layer.node.size.width {
            layer.node.position.x += layer.node.size.width * 2
        }
    }
}
```

### State Machine for Characters

```swift
enum PlayerState {
    case idle, running, jumping, falling, dead
}

class PlayerNode: SKSpriteNode {
    var state: PlayerState = .idle {
        didSet {
            guard state != oldValue else { return }
            removeAction(forKey: "animation")
            switch state {
            case .idle:
                run(.repeatForever(.animate(with: idleTextures, timePerFrame: 0.15)), withKey: "animation")
            case .running:
                run(.repeatForever(.animate(with: runTextures, timePerFrame: 0.08)), withKey: "animation")
            case .jumping:
                texture = jumpTexture
            case .falling:
                texture = fallTexture
            case .dead:
                run(.sequence([
                    .fadeOut(withDuration: 0.5),
                    .removeFromParent()
                ]))
            }
        }
    }
}
```

---

## Troubleshooting

Decision trees for the most common SpriteKit issues. Start with **debug overlays** before anything else.

### Step 0: Enable Debug Overlays

```swift
view.showsFPS = true
view.showsNodeCount = true
view.showsDrawCount = true
view.showsPhysics = true  // If showsPhysics shows no outlines, physics bodies aren't configured
```

### Physics Contacts Not Firing

```
didBegin(_:) never called
├─ physicsWorld.contactDelegate set?
│   └─ NO → physicsWorld.contactDelegate = self in didMove(to:)
├─ Class conforms to SKPhysicsContactDelegate?
│   └─ NO → Add conformance
├─ contactTestBitMask includes other body's category?
│   ├─ Print: (A.contactTestBitMask & B.categoryBitMask) != 0
│   └─ FIX: player.physicsBody?.contactTestBitMask = PhysicsCategory.enemy
├─ Bodies actually overlap? (Check showsPhysics)
│   └─ Bodies too small or offset → Fix body size/position
└─ Modifying world inside didBegin?
    └─ FIX: Flag for removal, process in update(_:)
```

**Diagnostic print:**
```swift
func didBegin(_ contact: SKPhysicsContact) {
    print("CONTACT: \(contact.bodyA.node?.name ?? "nil") (\(contact.bodyA.categoryBitMask)) <-> \(contact.bodyB.node?.name ?? "nil") (\(contact.bodyB.categoryBitMask))")
}
```

### Objects Tunneling Through Walls

```
Fast objects pass through thin walls
├─ Object speed > wall thickness × 60? → usesPreciseCollisionDetection = true
├─ Wall is edge body (zero area)? → Use volume body with isDynamic = false
├─ Wall < 10pt thick? → Thicken to at least 10pt
└─ Collision bitmasks correct? → Verify object.collisionBitMask & wall.categoryBitMask != 0
```

### Poor Frame Rate

```
FPS < 60
├─ showsNodeCount > 1000 → Remove off-screen nodes, use object pooling
├─ showsDrawCount > 50 → Use texture atlases, replace SKShapeNode, consolidate z-layers
├─ Many texture-based physics bodies → Simplify to circles/rectangles
├─ SKEffectNode without shouldRasterize → Set shouldRasterize = true for static content
└─ Heavy update() logic → Cache node references, spread work across frames
```

### Touches Not Registering

```
touchesBegan not called on node
├─ isUserInteractionEnabled = true? → Default is false on all non-scene nodes
├─ Node hidden or alpha = 0? → Hidden nodes don't receive touches
├─ Another node intercepting? → Print nodes(at: touchLocation) to check
├─ Using touch.location(in: self.view)? → WRONG: use touch.location(in: self) for scene coords
└─ SKNode (container) has zero frame → Use contains(point) or nodes(at:) for manual hit testing
```

### Memory Growth

```
Memory increases during gameplay
├─ showsNodeCount climbing? → Nodes spawned but not removed. Add cleanup or pooling
├─ Infinite emitters (numParticlesToEmit = 0)? → Set finite count or manually stop and remove
├─ Strong self in action closures? → Use [weak self] in SKAction.run
├─ Scene not deallocating? → Add deinit print, check for retain cycles
│   └─ Clean up in willMove(from:): removeAllActions(), removeAllChildren(), contactDelegate = nil
└─ Profile with Instruments → Allocations, filter by "SK"
```

### Scene Transition Crashes

```
Crash during or after transition
├─ EXC_BAD_ACCESS after transition → Old scene referenced by timer/delegate/observer
│   └─ FIX: Clean up in willMove(from:)
├─ Crash in didMove(to:) → guard let view = self.view
├─ Memory spike → Both scenes exist during transition; use .fade to reduce peak
└─ didMove called twice → Double-tap on transition trigger; disable after first tap
```

### Quick Reference

| Symptom | First Check | Most Likely Cause |
|---|---|---|
| Contacts don't fire | `contactDelegate` set? | Missing `contactTestBitMask` |
| Tunneling | Object speed vs wall thickness | Missing `usesPreciseCollisionDetection` |
| Low FPS | `showsDrawCount` | SKShapeNode in gameplay or missing atlas |
| Touches broken | `isUserInteractionEnabled`? | Default is `false` on non-scene nodes |
| Memory growth | `showsNodeCount` increasing? | Nodes created but never removed |
| Wrong positions | Y-axis direction | Using view coordinates instead of scene |
| Transition crash | `willMove(from:)` cleanup? | Strong references to old scene |
