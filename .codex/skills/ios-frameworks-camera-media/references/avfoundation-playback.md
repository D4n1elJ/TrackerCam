# AVFoundation Playback & Editing

Audio/video playback, composition, and export. For camera capture, see the main SKILL.md.

## AVPlayer

```swift
import AVKit

// Basic playback
let player = AVPlayer(url: videoURL)
let playerVC = AVPlayerViewController()
playerVC.player = player
present(playerVC, animated: true) { player.play() }

// SwiftUI
VideoPlayer(player: player)
    .onAppear { player.play() }
```

## AVPlayerItem

```swift
let asset = AVURLAsset(url: url)
let item = AVPlayerItem(asset: asset)

// Observe status
item.publisher(for: \.status)
    .sink { status in
        switch status {
        case .readyToPlay: player.play()
        case .failed: print(item.error)
        default: break
        }
    }

// Seek
await player.seek(to: CMTime(seconds: 30, preferredTimescale: 600))

// Rate
player.rate = 1.5  // 1.5x speed
```

## AVAudioSession

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .moviePlayback)
try session.setActive(true)
// Set category BEFORE creating AVPlayer
```

### Common Categories

| Category | Use |
|---|---|
| `.playback` | Audio/video playback (silences other apps) |
| `.ambient` | Background music (mixes with other apps) |
| `.record` | Recording audio |
| `.playAndRecord` | VoIP, recording while playing |
| `.soloAmbient` | Default — silences on ring/silent switch |

## AVAsset (Metadata & Inspection)

```swift
let asset = AVURLAsset(url: url)
let duration = try await asset.load(.duration)
let tracks = try await asset.load(.tracks)
let isPlayable = try await asset.load(.isPlayable)

// Video dimensions
if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
    let size = try await videoTrack.load(.naturalSize)
    let transform = try await videoTrack.load(.preferredTransform)
}
```

## AVComposition (Video Editing)

```swift
let composition = AVMutableComposition()

// Add video track
let videoTrack = composition.addMutableTrack(
    withMediaType: .video,
    preferredTrackID: kCMPersistentTrackID_Invalid
)

let asset = AVURLAsset(url: sourceURL)
let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first!
let duration = try await asset.load(.duration)

try videoTrack?.insertTimeRange(
    CMTimeRange(start: .zero, duration: duration),
    of: sourceVideoTrack,
    at: .zero
)

// Trim
let trimRange = CMTimeRange(
    start: CMTime(seconds: 5, preferredTimescale: 600),
    duration: CMTime(seconds: 10, preferredTimescale: 600)
)
try videoTrack?.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
```

## AVAssetExportSession

```swift
guard let exportSession = AVAssetExportSession(
    asset: composition,
    presetName: AVAssetExportPresetHighestQuality
) else { return }

exportSession.outputURL = outputURL
exportSession.outputFileType = .mp4

await exportSession.export()

switch exportSession.status {
case .completed: print("Export done")
case .failed: print(exportSession.error)
default: break
}
```

## Background Audio

Info.plist: `UIBackgroundModes` → `audio`

```swift
try AVAudioSession.sharedInstance().setCategory(.playback)
// Player continues when app is backgrounded
```

## Now Playing Info (Lock Screen Controls)

```swift
import MediaPlayer

var nowPlayingInfo = [String: Any]()
nowPlayingInfo[MPMediaItemPropertyTitle] = "Song Title"
nowPlayingInfo[MPMediaItemPropertyArtist] = "Artist"
nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration.seconds
MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

// Remote commands
let commandCenter = MPRemoteCommandCenter.shared()
commandCenter.playCommand.addTarget { _ in player.play(); return .success }
commandCenter.pauseCommand.addTarget { _ in player.pause(); return .success }
```
