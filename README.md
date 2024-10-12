# Ambience

Ambience is a Swift package that provides seamless integration of Apple Music's ambient (animated or motion) video artwork into iOS applications, enhancing the visual experience of music playback.

## Features

- Fetch ambient video artwork from Apple Music links
- Easy-to-use UIKit and SwiftUI components for displaying ambient videos
- Support for various playback controls and customizations

## Requirements

- iOS 16.0+
- Swift 5.9+

## Installation

### Swift Package Manager

To integrate Ambience into your Xcode project using Swift Package Manager, add it to the dependencies value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/zhangqifan/Ambience.git", .upToNextMajor(from: "1.0.0"))
]
```

## Usage

### Fetching Ambience Artwork

```swift
import Ambience

let musicItemURL = URL(string: "https://music.apple.com/your-music-link")!
do {
    let ambienceURL = try await AmbienceService.fetchAmbienceAsset(from: musicItemURL)
    // Use the ambienceURL to display the video
} catch {
    print("Error fetching ambience: \(error)")
}
```

### Displaying Ambience Artwork in UIKit with AVPlayer

```swift
import UIKit
import AVFoundation
import Ambience

class AmbienceViewController: UIViewController {
    private var playerView: AmbienceArtworkPlayerView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        playerView = AmbienceArtworkPlayerView()
        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerView)
        
        // Assuming you have already fetched the ambienceURL
        playerView.updatePlayerItem(with: ambienceURL)
        playerView.play()
    }
}
```

### Displaying Ambience Artwork in SwiftUI

```swift
import SwiftUI
import Ambience

struct ContentView: View {
    let ambienceURL: URL

    var body: some View {
        AmbienceArtworkPlayer(url: ambienceURL)
            .ambienceArtworkContentMode(.scaleAspectFit)
            .ambienceLooping(true)
            .ambienceAutoPlay(true)
            .aspectRatio(16/9, contentMode: .fit)
    }
}
```

## Customization

Ambience offers various customization options:
	•	Content mode
	•	Looping behavior
	•	Auto-play settings
Check the documentation for more detailed information on available customizations.

## Contributing

Contributions to Ambience are welcome! Please feel free to submit a Pull Request.

## License

Ambience is available under the MIT license. See the LICENSE file for more info.
