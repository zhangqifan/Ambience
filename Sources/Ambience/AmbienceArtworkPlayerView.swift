//
//  AmbienceArtworkPlayerView.swift
//  Ambience
//
//  Created by Shuhari on 2024/10/12.
//  Copyright © 2024 Shuhari. All rights reserved.
//
//  This file is part of the Ambience package.
//
//  Description:
//  AmbienceArtworkPlayerView is a custom view that wraps AVPlayer for playing
//  ambience artwork videos. It provides functionality for video playback control
//  and event handling, with both AppKit, UIKit and SwiftUI support.

import AVFoundation
import Combine
import SwiftUI

#if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Protocol defining the delegate methods for the `AmbienceArtworkPlayerView`.
public protocol AmbienceArtworkPlayerDelegate: AnyObject {
    /// Called when the player item's duration is updated.
    func ambiencePlayer(_ player: AmbienceArtworkPlayerView, didUpdateDuration duration: TimeInterval)
    
    /// Called when the player item is ready to play.
    func ambiencePlayerIsReadyToPlay(_ player: AmbienceArtworkPlayerView)
    
    /// Called when the player item is about to finish.
    func ambiencePlayerIsAboutToFinish(_ player: AmbienceArtworkPlayerView)
    
    /// Called when the player item has finished playing.
    func ambiencePlayerDidFinish(_ player: AmbienceArtworkPlayerView)
}

/// A custom view that wraps AVPlayer for ambience artwork video playback.
#if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
public class AmbienceArtworkPlayerView: UIView {
  // MARK: - Public Properties
  
  public weak var delegate: AmbienceArtworkPlayerDelegate?
  public var isLoopingEnabled: Bool = true
  public var shouldAutoPlay: Bool = true
  
  public var currentDuration: CMTime { player.currentItem?.duration ?? .zero }
  public var currentTime: CMTime { player.currentTime() }
  public var isPaused: Bool { player.timeControlStatus == .paused }
  
  public var artworkContentMode: UIView.ContentMode = .scaleAspectFit {
    didSet {
      updateVideoGravity()
    }
  }
  
  public var cornerRadius: CGFloat = 0 {
    didSet {
      updateCornerProperties()
    }
  }
  
  public var cornerCurve: CALayerCornerCurve = .continuous {
    didSet {
      updateCornerProperties()
    }
  }
  
  // MARK: - Private Properties
  
  private let player = AVPlayer()
  private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  private var timeObserver: Any?
  private var itemObservation: NSKeyValueObservation?
  
  // MARK: - Initialization
  
  override public init(frame: CGRect) {
    super.init(frame: frame)
    setupPlayer()
    setupNotifications()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupPlayer()
    setupNotifications()
  }
  
  deinit {
    removeNotifications()
    removePlayerObservers()
  }
  
  override public class var layerClass: AnyClass { AVPlayerLayer.self }
  
  // MARK: - Public Methods
  
  public func updatePlayerItem(with url: URL, shouldAutoPlay: Bool = true) {
    self.shouldAutoPlay = shouldAutoPlay
    let playerItem = AVPlayerItem(url: url)
    
    removePlayerObservers()
    player.replaceCurrentItem(with: playerItem)
    addPlayerObservers()
    
    if shouldAutoPlay {
      play()
    }
  }
  
  public func play() {
    player.play()
  }
  
  public func pause() {
    player.pause()
  }
  
  public func seek(to time: CMTime, completion: @escaping () -> Void) {
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      guard let self = self, finished else { return }
      self.play()
      completion()
    }
  }
  
  // MARK: - Private Methods
  
  private func setupPlayer() {
    playerLayer.player = player
    updateVideoGravity()
    updateCornerProperties()
  }
  
  private func setupNotifications() {
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd), name: .AVPlayerItemDidPlayToEndTime, object: nil)
  }
  
  private func removeNotifications() {
    NotificationCenter.default.removeObserver(self)
  }
  
  private func addPlayerObservers() {
    itemObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard let self = self else { return }
      if item.status == .readyToPlay {
        self.delegate?.ambiencePlayerIsReadyToPlay(self)
        self.delegate?.ambiencePlayer(self, didUpdateDuration: CMTimeGetSeconds(item.duration))
      }
    }
    
    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      guard let self = self, let duration = self.player.currentItem?.duration else { return }
      let timeLeft = CMTimeSubtract(duration, time)
      if timeLeft.seconds <= 1.2 {
        self.delegate?.ambiencePlayerIsAboutToFinish(self)
      }
    }
  }
  
  private func removePlayerObservers() {
    itemObservation?.invalidate()
    itemObservation = nil
    
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
  }
  
  private func updateVideoGravity() {
    switch artworkContentMode {
    case .scaleAspectFit:
      playerLayer.videoGravity = .resizeAspect
    case .scaleAspectFill:
      playerLayer.videoGravity = .resizeAspectFill
    default:
      playerLayer.videoGravity = .resize
    }
  }
  
  private func updateCornerProperties() {
    layer.cornerRadius = cornerRadius
    layer.cornerCurve = cornerCurve
    layer.masksToBounds = cornerRadius > 0
  }
  
  @objc private func playerItemDidReachEnd(_ notification: Notification) {
    guard let playerItem = notification.object as? AVPlayerItem,
          playerItem == player.currentItem else { return }
    
    delegate?.ambiencePlayerDidFinish(self)
    
    if isLoopingEnabled {
      player.seek(to: .zero)
      player.play()
    }
  }
}
#endif

#if os(macOS)
public class AmbienceArtworkPlayerView: NSView {
  // MARK: - Public Properties
  
  public weak var delegate: AmbienceArtworkPlayerDelegate?
  public var isLoopingEnabled: Bool = true
  public var shouldAutoPlay: Bool = true
  
  public var currentDuration: CMTime { player.currentItem?.duration ?? .zero }
  public var currentTime: CMTime { player.currentTime() }
  public var isPaused: Bool { player.timeControlStatus == .paused }
  
    public var artworkContentMode: AVLayerVideoGravity = .resizeAspect {
    didSet {
      updateVideoGravity()
    }
  }
  
  public var cornerRadius: CGFloat = 0 {
    didSet {
      updateCornerProperties()
    }
  }
  
  public var cornerCurve: CALayerCornerCurve = .continuous {
    didSet {
      updateCornerProperties()
    }
  }
  
  // MARK: - Private Properties
  
  private let player = AVPlayer()
  private var playerLayer: AVPlayerLayer!
  private var timeObserver: Any?
  private var itemObservation: NSKeyValueObservation?
  
  // MARK: - Initialization
  
  override init(frame: NSRect) {
    super.init(frame: frame)
    setupPlayer()
    setupNotifications()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupPlayer()
    setupNotifications()
  }
  
  deinit {
    removeNotifications()
    removePlayerObservers()
  }
  
  // MARK: - Public Methods
  
  public func updatePlayerItem(with url: URL, shouldAutoPlay: Bool = true) {
    self.shouldAutoPlay = shouldAutoPlay
    let playerItem = AVPlayerItem(url: url)
    
    removePlayerObservers()
    player.replaceCurrentItem(with: playerItem)
    addPlayerObservers()
    
    if shouldAutoPlay {
      play()
    }
  }
  
  public func play() {
    player.play()
  }
  
  public func pause() {
    player.pause()
  }
  
  public func seek(to time: CMTime, completion: @escaping () -> Void) {
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      guard let self = self, finished else { return }
      self.play()
      completion()
    }
  }
  
  // MARK: - Private Methods
  
  private func setupPlayer() {
    playerLayer = AVPlayerLayer()
    playerLayer.player = player
    layer = playerLayer
    wantsLayer = true
    updateVideoGravity()
    updateCornerProperties()
  }
  
  private func setupNotifications() {
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd), name: .AVPlayerItemDidPlayToEndTime, object: nil)
  }
  
  private func removeNotifications() {
    NotificationCenter.default.removeObserver(self)
  }
  
  private func addPlayerObservers() {
    itemObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard let self = self else { return }
      if item.status == .readyToPlay {
        self.delegate?.ambiencePlayerIsReadyToPlay(self)
        self.delegate?.ambiencePlayer(self, didUpdateDuration: CMTimeGetSeconds(item.duration))
      }
    }
    
    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      guard let self = self, let duration = self.player.currentItem?.duration else { return }
      let timeLeft = CMTimeSubtract(duration, time)
      if timeLeft.seconds <= 1.2 {
        self.delegate?.ambiencePlayerIsAboutToFinish(self)
      }
    }
  }
  
  private func removePlayerObservers() {
    itemObservation?.invalidate()
    itemObservation = nil
    
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
  }
  
  private func updateVideoGravity() {
    playerLayer.videoGravity = artworkContentMode
  }
  
  private func updateCornerProperties() {
    layer?.cornerRadius = cornerRadius
    layer?.cornerCurve = cornerCurve
    layer?.masksToBounds = cornerRadius > 0
  }
  
  @objc private func playerItemDidReachEnd(_ notification: Notification) {
    guard let playerItem = notification.object as? AVPlayerItem,
          playerItem == player.currentItem else { return }
    
    delegate?.ambiencePlayerDidFinish(self)
    
    if isLoopingEnabled {
      player.seek(to: .zero)
      player.play()
    }
  }
}
#endif

// MARK: - SwiftUI Support

#if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public struct AmbienceArtworkPlayer: UIViewRepresentable {
    var url: URL?
    var delegate: AmbienceArtworkPlayerDelegate?
    var isLoopingEnabled: Bool
    var shouldAutoPlay: Bool
    var artworkContentMode: UIView.ContentMode
    var cornerRadius: CGFloat
    var cornerCurve: CALayerCornerCurve

    /// Initializes a new instance of AmbienceArtworkPlayer.
    ///
    /// - Parameters:
    ///   - url: The URL of the artwork to be played.
    ///   - delegate: The delegate to receive player events.
    ///   - isLoopingEnabled: Determines if the player should loop the artwork.
    ///   - shouldAutoPlay: Determines if the player should start playing automatically.
    ///   - artworkContentMode: The content mode for displaying the artwork.
    ///   - cornerRadius: The corner radius of the player view.
    ///   - cornerCurve: The corner curve style of the player view.
    public init(
        url: URL?,
        delegate: AmbienceArtworkPlayerDelegate? = nil,
        isLoopingEnabled: Bool = true,
        shouldAutoPlay: Bool = true,
        artworkContentMode: UIView.ContentMode = .scaleAspectFit,
        cornerRadius: CGFloat = 0,
        cornerCurve: CALayerCornerCurve = .continuous
    ) {
        self.url = url
        self.delegate = delegate
        self.isLoopingEnabled = isLoopingEnabled
        self.shouldAutoPlay = shouldAutoPlay
        self.artworkContentMode = artworkContentMode
        self.cornerRadius = cornerRadius
        self.cornerCurve = cornerCurve
    }

    public func makeUIView(context: Context) -> AmbienceArtworkPlayerView {
        let view = AmbienceArtworkPlayerView()
        view.delegate = delegate
        view.isLoopingEnabled = isLoopingEnabled
        view.shouldAutoPlay = shouldAutoPlay
        view.artworkContentMode = artworkContentMode
        view.cornerRadius = cornerRadius
        view.cornerCurve = cornerCurve
        return view
    }

    public func updateUIView(_ uiView: AmbienceArtworkPlayerView, context: Context) {
        if let url = url {
            uiView.updatePlayerItem(with: url, shouldAutoPlay: shouldAutoPlay)
        }
        uiView.isLoopingEnabled = isLoopingEnabled
        uiView.artworkContentMode = artworkContentMode
        uiView.cornerRadius = cornerRadius
        uiView.cornerCurve = cornerCurve
    }
}

public extension AmbienceArtworkPlayer {
    func ambienceArtworkContentMode(_ mode: UIView.ContentMode) -> AmbienceArtworkPlayer {
        var view = self
        view.artworkContentMode = mode
        return view
    }

    func ambienceLooping(_ isLooping: Bool) -> AmbienceArtworkPlayer {
        var view = self
        view.isLoopingEnabled = isLooping
        return view
    }

    func ambienceAutoPlay(_ shouldAutoPlay: Bool) -> AmbienceArtworkPlayer {
        var view = self
        view.shouldAutoPlay = shouldAutoPlay
        return view
    }

    func ambienceCornerRadius(_ radius: CGFloat, curve: CALayerCornerCurve = .continuous) -> AmbienceArtworkPlayer {
        var view = self
        view.cornerRadius = radius
        view.cornerCurve = curve
        return view
    }
}
#endif

#if os(macOS)
public struct AmbienceArtworkPlayer: NSViewRepresentable {

    /// The URL of the artwork to be played.
    var url: URL?

    /// The delegate to receive player events.
    var delegate: AmbienceArtworkPlayerDelegate?

    /// Determines if the player should loop the artwork.
    var isLoopingEnabled: Bool

    /// Determines if the player should start playing automatically.
    var shouldAutoPlay: Bool

    /// The content mode for displaying the artwork.
    var artworkContentMode: AVLayerVideoGravity

    /// The corner radius of the player view.
    var cornerRadius: CGFloat

    /// The corner curve style of the player view.
    var cornerCurve: CALayerCornerCurve

    /// Initializes a new instance of AmbienceArtworkPlayerMac.
    ///
    /// - Parameters:
    ///   - url: The URL of the artwork to be played.
    ///   - delegate: The delegate to receive player events.
    ///   - isLoopingEnabled: Determines if the player should loop the artwork.
    ///   - shouldAutoPlay: Determines if the player should start playing automatically.
    ///   - artworkContentMode: The content mode for displaying the artwork.
    ///   - cornerRadius: The corner radius of the player view.
    ///   - cornerCurve: The corner curve style of the player view.
    public init(
        url: URL?,
        delegate: AmbienceArtworkPlayerDelegate? = nil,
        isLoopingEnabled: Bool = true,
        shouldAutoPlay: Bool = true,
        artworkContentMode: AVLayerVideoGravity = .resizeAspect,
        cornerRadius: CGFloat = 0,
        cornerCurve: CALayerCornerCurve = .continuous
    ) {
        self.url = url
        self.delegate = delegate
        self.isLoopingEnabled = isLoopingEnabled
        self.shouldAutoPlay = shouldAutoPlay
        self.artworkContentMode = artworkContentMode
        self.cornerRadius = cornerRadius
        self.cornerCurve = cornerCurve
    }

    public func makeNSView(context: Context) -> AmbienceArtworkPlayerView {
        let view = AmbienceArtworkPlayerView()
        view.delegate = delegate
        view.isLoopingEnabled = isLoopingEnabled
        view.shouldAutoPlay = shouldAutoPlay
        view.artworkContentMode = artworkContentMode
        view.cornerRadius = cornerRadius
        view.cornerCurve = cornerCurve
        return view
    }

    public func updateNSView(_ nsView: AmbienceArtworkPlayerView, context: Context) {
        if let url = url {
            nsView.updatePlayerItem(with: url, shouldAutoPlay: shouldAutoPlay)
        }
        nsView.isLoopingEnabled = isLoopingEnabled
        nsView.artworkContentMode = artworkContentMode
        nsView.cornerRadius = cornerRadius
        nsView.cornerCurve = cornerCurve
    }
}

public extension AmbienceArtworkPlayer {

    /// Sets the content mode for the artwork.
    ///
    /// - Parameter mode: The desired content mode.
    /// - Returns: A new instance of AmbienceArtworkPlayerMac with the updated content mode.
    func ambienceArtworkContentMode(_ mode: AVLayerVideoGravity) -> AmbienceArtworkPlayer {
        var view = self
        view.artworkContentMode = mode
        return view
    }

    /// Sets whether the artwork should loop.
    ///
    /// - Parameter isLooping: A boolean indicating whether looping should be enabled.
    /// - Returns: A new instance of AmbienceArtworkPlayerMac with the updated looping setting.
    func ambienceLooping(_ isLooping: Bool) -> AmbienceArtworkPlayer {
        var view = self
        view.isLoopingEnabled = isLooping
        return view
    }

    /// Sets whether the artwork should auto-play.
    ///
    /// - Parameter shouldAutoPlay: A boolean indicating whether auto-play should be enabled.
    /// - Returns: A new instance of AmbienceArtworkPlayerMac with the updated auto-play setting.
    func ambienceAutoPlay(_ shouldAutoPlay: Bool) -> AmbienceArtworkPlayer {
        var view = self
        view.shouldAutoPlay = shouldAutoPlay
        return view
    }

    /// Sets the corner radius and curve of the player view.
    ///
    /// - Parameters:
    ///   - radius: The desired corner radius.
    ///   - curve: The desired corner curve style.
    /// - Returns: A new instance of AmbienceArtworkPlayerMac with the updated corner properties.
    func ambienceCornerRadius(_ radius: CGFloat, curve: CALayerCornerCurve = .continuous) -> AmbienceArtworkPlayer {
        var view = self
        view.cornerRadius = radius
        view.cornerCurve = curve
        return view
    }
}
#endif
