# SpriteKit Quick Reference

## Purpose

Opinionated guide for building 2D games and interactive scenes with SpriteKit on iOS 26+. Covers scene setup, node hierarchies, physics, actions, and SwiftUI integration.

## How to Use

1. **Pick the right framework** using the decision tree below
2. **Set up your scene** following the lifecycle patterns
3. **Check anti-patterns** before shipping
4. **For full API details**, read `references/spritekit-patterns.md`

## Framework Decision Tree

```
2D sprites, tiles, or particle effects?         -> SpriteKit
3D models with simple lighting?                  -> SceneKit
AR/VR or complex 3D with PBR materials?          -> RealityKit
Lightweight 2D drawing (charts, custom shapes)?  -> SwiftUI Canvas
Simple shape animation, no physics needed?       -> SwiftUI + .animation
```

| Framework | Best For | Physics | Rendering |
|---|---|---|---|
| SpriteKit | 2D games, particle effects, tile maps | Built-in 2D physics | GPU-accelerated sprite batching |
| SceneKit | 3D scenes, casual 3D games | Built-in 3D physics | PBR and custom shaders |
| RealityKit | AR experiences, visionOS | Full 3D physics + anchoring | PBR, spatial audio |
| SwiftUI Canvas | Custom drawing, data viz | None | Core Graphics |

## Scene Setup Quick Start

```swift
import SpriteKit
import SwiftUI

// 1. Define the scene
class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self

        let player = SKSpriteNode(imageNamed: "player")
        player.position = CGPoint(x: size.width / 2, y: size.height / 2)
        player.physicsBody = SKPhysicsBody(circleOfRadius: player.size.width / 2)
        addChild(player)
    }

    override func update(_ currentTime: TimeInterval) {
        // Called every frame -- keep lightweight
    }
}

// 2. Host in SwiftUI
struct GameView: View {
    var body: some View {
        SpriteView(scene: GameScene(size: CGSize(width: 390, height: 844)))
            .ignoresSafeArea()
    }
}
```

## Node Type Quick Reference

| Node | Purpose | When to Use |
|---|---|---|
| `SKSpriteNode` | Textured rectangle | Characters, items, backgrounds |
| `SKShapeNode` | Vector path rendering | Debug shapes, dynamic geometry |
| `SKLabelNode` | Text rendering | Score, HUD text |
| `SKEmitterNode` | Particle system | Fire, smoke, sparks, trails |
| `SKCameraNode` | Viewport control | Scrolling levels, zoom |
| `SKTileMapNode` | Grid-based tile rendering | Platformer levels, terrain |
| `SKEffectNode` | Core Image filter host | Blur, glow, distortion |
| `SKCropNode` | Masking | Reveal effects, health bars |

## Action Quick Reference

| Intent | Action | Example |
|---|---|---|
| Move | `.move(to:duration:)` | Slide to position |
| Fade | `.fadeOut(withDuration:)` | Death animation |
| Scale | `.scale(to:duration:)` | Power-up pulse |
| Rotate | `.rotate(byAngle:duration:)` | Spinning coin |
| Sequence | `.sequence([...])` | Move then fade |
| Group | `.group([...])` | Move AND fade simultaneously |
| Repeat | `.repeatForever(_:)` | Idle animation loop |
| Wait | `.wait(forDuration:)` | Delay between actions |
| Run block | `.run { ... }` | Trigger logic mid-sequence |
| Animate textures | `.animate(with:timePerFrame:)` | Sprite sheet animation |

```swift
// Common pattern: shoot then remove
let bullet = SKSpriteNode(imageNamed: "bullet")
bullet.position = player.position
addChild(bullet)

let move = SKAction.move(to: CGPoint(x: bullet.position.x, y: size.height + 50), duration: 0.8)
let remove = SKAction.removeFromParent()
bullet.run(.sequence([move, remove]))
```

## Physics Category Pattern

```swift
struct PhysicsCategory {
    static let none:    UInt32 = 0
    static let player:  UInt32 = 0b0001  // 1
    static let enemy:   UInt32 = 0b0010  // 2
    static let bullet:  UInt32 = 0b0100  // 4
    static let wall:    UInt32 = 0b1000  // 8
}

// Setup
player.physicsBody?.categoryBitMask = PhysicsCategory.player
player.physicsBody?.contactTestBitMask = PhysicsCategory.enemy
player.physicsBody?.collisionBitMask = PhysicsCategory.wall
```

## Anti-Patterns

### Scene & Lifecycle

| Mistake | Fix |
|---|---|
| Creating a new `SKScene` every SwiftUI body call | Create scene once with `@State` or `@StateObject`, pass to `SpriteView` |
| Heavy work in `update(_:)` | Only do per-frame delta logic; defer spawning/loading to actions or timers |
| Not setting `scaleMode` | Always set `.scaleMode` in `init` or `didMove(to:)` -- `.resizeFill` or `.aspectFill` |
| Using `SKShapeNode` for many static shapes | `SKShapeNode` is expensive; bake to texture with `view.texture(from:)` or use sprites |
| No cleanup in `willMove(from:)` | Always clean up: `removeAllActions(); removeAllChildren(); physicsWorld.contactDelegate = nil` |

### Physics

| Mistake | Fix |
|---|---|
| Forgetting `contactTestBitMask` | No contact callback fires without it -- always set it explicitly |
| Using pixel-perfect physics bodies | Use simple shapes (circle, rectangle) -- complex paths kill performance |
| Setting `velocity` in `update(_:)` every frame | Use forces/impulses instead; direct velocity overrides physics simulation |
| Modifying physics world inside `didBegin`/`didEnd` | Flag nodes for removal, process in `update(_:)` -- world modifications mid-callback cause missed contacts and crashes |
| Using `SKAction.move` on physics-controlled nodes | Actions override physics position, causing jitter and missed collisions -- use forces/impulses instead |

### Performance

| Mistake | Fix |
|---|---|
| One texture per sprite file | Use texture atlases -- reduces draw calls dramatically |
| Not reusing `SKTexture` instances | Load textures once, store in a dictionary or atlas reference |
| Thousands of `SKShapeNode` instances | Convert to sprites or use `SKTileMapNode` for grids |
| Spawning without removing | Always pair spawns with `removeFromParent()` -- leaked nodes tank FPS |
| Not profiling | Use Xcode's SpriteKit FPS overlay: `view.showsFPS = true; view.showsNodeCount = true` |

### SwiftUI Integration

| Mistake | Fix |
|---|---|
| Mutating scene from SwiftUI body | Use a coordinator pattern or post notifications; never reach into scene from body |
| `SpriteView` without `ignoresSafeArea()` | Scene gets clipped; almost always want full bleed |
| Passing `isPaused` via binding to scene | Use `SpriteView(scene:isPaused:)` parameter directly |

## Common Patterns

### Infinite Scrolling Background

```swift
func setupBackground() {
    for i in 0...1 {
        let bg = SKSpriteNode(imageNamed: "background")
        bg.anchorPoint = .zero
        bg.position = CGPoint(x: 0, y: bg.size.height * CGFloat(i))
        bg.name = "background"
        bg.zPosition = -1
        addChild(bg)
    }
}

override func update(_ currentTime: TimeInterval) {
    enumerateChildNodes(withName: "background") { node, _ in
        node.position.y -= 2
        if node.position.y < -node.frame.size.height {
            node.position.y += node.frame.size.height * 2
        }
    }
}
```

### HUD Layer with Camera

```swift
let camera = SKCameraNode()
addChild(camera)
self.camera = camera

// HUD stays fixed on screen
let scoreLabel = SKLabelNode(text: "Score: 0")
scoreLabel.position = CGPoint(x: 0, y: size.height / 2 - 60)
camera.addChild(scoreLabel)  // Attach to camera, not scene
```

## SpriteView Options

```swift
// Basic
SpriteView(scene: scene)

// With options
SpriteView(
    scene: scene,
    transition: nil,
    isPaused: false,
    preferredFramesPerSecond: 60
)

// With debug overlay
SpriteView(scene: scene, debugOptions: [.showsFPS, .showsNodeCount, .showsPhysics])
```

## Code Review Checklist

### Physics
- [ ] Every physics body has explicit `categoryBitMask`
- [ ] Every physics body has explicit `collisionBitMask` (not default `0xFFFFFFFF`)
- [ ] Bodies needing callbacks have `contactTestBitMask` set
- [ ] `physicsWorld.contactDelegate` is assigned in `didMove(to:)`
- [ ] No world modifications inside `didBegin`/`didEnd` -- flag and defer to `update(_:)`
- [ ] Fast objects use `usesPreciseCollisionDetection`
- [ ] No `SKAction.move`/`rotate` on physics-controlled nodes

### Actions & Memory
- [ ] Repeating actions use `withKey:` for cancellation
- [ ] `SKAction.run` closures use `[weak self]`
- [ ] One-shot emitters are removed after emission

### Performance
- [ ] Debug overlays enabled during development
- [ ] `ignoresSiblingOrder = true` on SKView
- [ ] No `SKShapeNode` in gameplay (use pre-rendered textures)
- [ ] Texture atlases used for related sprites
- [ ] Off-screen nodes removed or recycled

### Scene Management
- [ ] `willMove(from:)` cleans up actions, children, and delegates
- [ ] Scene data passed via shared `@Observable` model, not node properties
- [ ] Camera used for viewport control with HUD attached as children

## Full Reference

For the complete API -- scene lifecycle, node hierarchy details, full physics setup, action composition, texture atlas workflow, tile maps, particle effects, camera patterns, and performance tuning -- read `references/spritekit-patterns.md`.

## Global Rules

| Rule | Value |
|---|---|
| Default scale mode | `.aspectFill` for games, `.resizeFill` for utility scenes |
| Scene creation | Once, stored in `@State`; never recreated per body call |
| Physics body shapes | Simple primitives (circle, rect) unless proven too imprecise |
| Texture loading | Atlas-based; preload with `SKTextureAtlas.preloadTextureAtlases` |
| Node cleanup | Every spawned node must have a removal path |
| Debug overlays | Enable `showsFPS` + `showsNodeCount` during development |
| Deployment target | iOS 26+ only -- no `@available` checks |
