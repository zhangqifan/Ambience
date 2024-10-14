# Ambience

Ambience is a Swift package that provides seamless integration of Apple Music's ambient (animated or motion) video artwork into iOS/visionOS/macOS/tvOS and watchOS applications, enhancing the visual experience of music playback.

## Features

- Fetch ambient video artwork from Apple Music links
- Easy-to-use UIKit, AppKit and SwiftUI components for displaying ambient videos
- Support for various playback controls and customizations

## Requirements

- iOS 16.0+
- visionOS 1.0+
- macOS 14.0+
- tvOS 16.0+
- watchOS 9.0+
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

// Example Apple Music playlist link
let musicItemURL = URL(string: "https://music.apple.com/us/playlist/k-pop-rewind/pl.fa1e4b518c7244a086390d49aeb65d1e")!

do {
    let ambienceURL = try await AmbienceService.fetchAmbienceAsset(from: musicItemURL)
    // Use the ambienceURL to display the video
    print("Ambience URL: \(ambienceURL)")
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
- Content mode
- Looping behavior
- Auto-play settings
  
Check the documentation for more detailed information on available customizations.

## Companion App

To help you explore and test the capabilities of Ambience, I've included a companion app in this repository. This app demonstrates real-world usage of the Ambience package and offers the following features:

1. **Music Item Link Testing**: 
   - Input Apple Music item links directly
   - Fetch and display Ambience resources for the input link
   - Test the package's ability to handle various music item types

2. **Personal Recommendations**:
   - For users with an active Apple Music subscription
   - Displays personalized music recommendations
   - Quickly preview Ambience resources for recommended items

This companion app serves as both a demonstration of Ambience's features and a practical tool for developers to test the package's functionality.

## Setting Up and Using the Companion App

To use the Companion app, you need to set up MusicKit for your own bundle identifier. Follow these steps:

1. Clone this repository
2. Open the `Ambience/AmbienceCompanion/AmbienceCompanion.xcodeproj` file in Xcode
3. Change the bundle identifier to your own unique identifier

### Enabling MusicKit

1. Visit the [Apple Developer Portal](https://developer.apple.com)
2. Navigate to `Certificates, Identifiers & Profiles`
3. Select `Identifiers` from the left panel
4. Find your App's Bundle Identifier from the list and select it
5. Under `Services`, ensure `MusicKit` is enabled. If not, enable it

### Running the App

After setting up MusicKit:

1. Build and run the app on your iOS device or simulator
2. Use the app to:
   - Test Ambience resources by inputting Apple Music links
   - Browse your personal Apple Music recommendations and preview their Ambience resources

Note: To use the personal recommendations feature, ensure you're signed in to your Apple Music account on the device.

## Contributing

Contributions to Ambience are welcome! Please feel free to submit a Pull Request.

## License

Ambience is available under the MIT license. See the LICENSE file for more info.
