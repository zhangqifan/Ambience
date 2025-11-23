//
//  HLSAssetManager.swift
//  Ambience
//
//  Created by Shuhari on 2024/10/12.
//  Copyright © 2024 Shuhari. All rights reserved.
//

import AVFoundation
import Foundation
import os

/// Manages downloading and caching of HLS assets.
/// This class is a singleton that handles the entire lifecycle of HLS video assets,
/// including downloading, storing with a predictable filename, and enforcing a cache limit.
actor HLSAssetManager: NSObject {
    static let shared = HLSAssetManager()
    
    // MARK: - Public Properties
    
    /// Current download status
    public private(set) var isDownloading = false
    
    /// Progress callback for download updates
    public var onProgressUpdate: ((DownloadProgress) -> Void)?
    
    /// Enable or disable detailed debug logging
    /// - Note: Changing this after initialization will not affect sub-managers
    public var enableDebugLogging: Bool {
        get { configuration.enableDebugLogging }
        set {
            var mutableConfig = configuration
            mutableConfig.enableDebugLogging = newValue
        }
    }
    
    // MARK: - Private Properties
    
    private var configuration: HLSAssetConfiguration
    private let logger: Logger
    private var downloadSession: AVAssetDownloadURLSession!
    private let cacheManager: CacheManager
    private let variantSelector: VariantSelector
    private let filenameStrategy: FilenameStrategy
    
    // Download coordination
    private var activeDownloadTasks: [URL: Task<URL, Error>] = [:]
    private var downloadStates: [AVAssetDownloadTask: DownloadState] = [:]
    
    // MARK: - Initialization
    
    override private init() {
        // Initialize configuration from AmbienceService settings
        self.configuration = HLSAssetConfiguration(
            cacheLimit: AmbienceService.cacheLimit,
            targetBitrate: AmbienceService.targetBitrate,
            enableDebugLogging: false  // Default to false, can be changed via public API
        )
        
        guard configuration.isValid else {
            fatalError("Invalid HLS asset configuration")
        }
        
        // Initialize logger
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.ambience",
            category: "HLSAssetManager"
        )
        
        // Initialize cache directory
        let fileManager = FileManager.default
        let cacheBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheDirectory = cacheBaseURL.appendingPathComponent("HLSAssets")
        
        // Initialize sub-managers with configuration
        self.cacheManager = CacheManager(
            cacheDirectory: cacheDirectory,
            cacheLimit: configuration.cacheLimit,
            logger: logger,
            enableDebugLogging: configuration.enableDebugLogging
        )
        self.variantSelector = VariantSelector(
            logger: logger,
            enableDebugLogging: configuration.enableDebugLogging
        )
        self.filenameStrategy = FilenameStrategy(
            logger: logger,
            enableDebugLogging: configuration.enableDebugLogging
        )
        
        super.init()
        
        // Setup download session (MUST use background configuration for AVAssetDownloadURLSession)
        let sessionConfig = URLSessionConfiguration.background(
            withIdentifier: "com.ambience.hlsAssetManager.\(UUID().uuidString)"
        )
        sessionConfig.isDiscretionary = false  // Download immediately
        sessionConfig.sessionSendsLaunchEvents = true  // Support background downloads
        
        self.downloadSession = AVAssetDownloadURLSession(
            configuration: sessionConfig,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue.main
        )
        
        if configuration.enableDebugLogging {
            logger.info("HLS Asset Manager initialized")
        }
    }
    
    // MARK: - Public Methods
    
    /// Downloads an HLS asset from a remote URL and stores it in the cache
    /// - Parameter remoteURL: The source URL of the music item
    /// - Returns: The local URL where the cached asset is stored
    /// - Throws: `HLSAssetError` if download fails
    /// - Note: If the asset is already being downloaded, awaits the result of the existing download
    func getAsset(from remoteURL: URL) async throws -> URL {
        if configuration.enableDebugLogging {
            logger.info("Fetching asset for: \(remoteURL.lastPathComponent)")
        }
        
        // Check cache first
        if let cachedURL = await cacheManager.getCachedAssetURL(for: remoteURL) {
            if configuration.enableDebugLogging {
                logger.info("Cache hit, returning: \(cachedURL.lastPathComponent)")
            }
            return cachedURL
        }
        
        // Fetch HLS URL from HTML
        if configuration.enableDebugLogging {
            logger.info("Fetching ambience artwork URL from HTML")
        }
        let htmlContent = try await HTMLFetcher.fetchHTMLContent(from: remoteURL)
        let hlsURL = try AmbienceArtworkExtractor.extractAmbienceArtworkURL(from: htmlContent)
        
        if configuration.enableDebugLogging {
            logger.info("HLS URL extracted: \(hlsURL.lastPathComponent)")
        }
        
        // Check if download is already in progress
        if let existingTask = activeDownloadTasks[hlsURL] {
            if configuration.enableDebugLogging {
                logger.info("Download already in progress, awaiting completion")
            }
            return try await existingTask.value
        }
        
        // Start new download
        if configuration.enableDebugLogging {
            logger.info("Starting download for: \(hlsURL.lastPathComponent)")
        }
        
        let downloadTask = Task { [weak self] in
            guard let self = self else {
                throw HLSAssetError.downloadLocationNotFound
            }
            
            defer {
                Task {
                    await self.cleanupDownloadTask(for: hlsURL)
                }
            }
            
            return try await self.performDownload(hlsURL: hlsURL, sourceURL: remoteURL)
        }
        
        activeDownloadTasks[hlsURL] = downloadTask
        isDownloading = true
        
        let finalURL = try await downloadTask.value
        
        if configuration.enableDebugLogging {
            logger.info("Asset download complete: \(finalURL.lastPathComponent)")
        }
        
        return finalURL
    }
    
    // MARK: - Private Methods
    
    private func performDownload(hlsURL: URL, sourceURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                let asset = AVURLAsset(url: hlsURL)
                
                // Load available video variants
                let variants: [AVAssetVariant]
                do {
                    variants = try await asset.load(.variants)
                } catch {
                    logger.error("Failed to load variants: \(error.localizedDescription)")
                    continuation.resume(throwing: HLSAssetError.failedToLoadVariants(underlying: error))
                    return
                }
                
                guard !variants.isEmpty else {
                    logger.error("No video variants available for asset")
                    continuation.resume(throwing: HLSAssetError.noVariantsFound)
                    return
                }
                
                // Select best variant
                let selectedVariant = variantSelector.selectBestVariant(
                    from: variants,
                    targetBitrate: configuration.targetBitrate
                )
                
                // Prepare download options
                var options: [String: Any] = [:]
                if let variant = selectedVariant, let bitrate = variant.averageBitRate {
                    options[AVAssetDownloadTaskMinimumRequiredMediaBitrateKey] = bitrate
                }
                
                // Add media selection
                if #available(macOS 13.0, iOS 16.0, *) {
                    if let mediaSelection = try? await asset.load(.preferredMediaSelection) {
                        options[AVAssetDownloadTaskMediaSelectionKey] = mediaSelection
                    }
                } else {
                    options[AVAssetDownloadTaskMediaSelectionKey] = asset.preferredMediaSelection
                }
                
                // Create download task
                guard let task = downloadSession.makeAssetDownloadTask(
                    asset: asset,
                    assetTitle: hlsURL.lastPathComponent,
                    assetArtworkData: nil,
                    options: options.isEmpty ? nil : options
                ) else {
                    logger.error("Failed to create download task")
                    continuation.resume(throwing: HLSAssetError.failedToCreateDownloadTask)
                    return
                }
                
                // Store download state for tracking
                let state = DownloadState(
                    task: task,
                    continuation: continuation,
                    sourceURL: sourceURL,
                    hlsURL: hlsURL,
                    downloadLocation: nil,
                    destinationURL: nil
                )
                downloadStates[task] = state
                
                // Start download
                task.resume()
                
                if configuration.enableDebugLogging {
                    logger.info("Download task started")
                }
            }
        }
    }
    
    private func cleanupDownloadTask(for hlsURL: URL) {
        activeDownloadTasks.removeValue(forKey: hlsURL)
        if activeDownloadTasks.isEmpty {
            isDownloading = false
        }
    }
}

// MARK: - AVAssetDownloadDelegate

extension HLSAssetManager: AVAssetDownloadDelegate {
    
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didResolve resolvedMediaSelection: AVMediaSelection
    ) {
        // Media selection resolved - no logging needed unless debug mode
        Task {
            if await self.configuration.enableDebugLogging {
                logger.info("Media selection resolved")
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        // Calculate download progress
        let expectedDuration = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        var loadedDuration: TimeInterval = 0
        
        for value in loadedTimeRanges {
            loadedDuration += CMTimeGetSeconds(value.timeRangeValue.duration)
        }
        
        let percentComplete = expectedDuration > 0 ? (loadedDuration / expectedDuration) * 100 : 0
        
        // Notify progress callback
        let progress = DownloadProgress(
            url: assetDownloadTask.urlAsset.url,
            percentComplete: percentComplete,
            loadedDuration: loadedDuration,
            expectedDuration: expectedDuration
        )
        
        Task {
            if await self.configuration.enableDebugLogging {
                logger.info("Download progress: \(String(format: "%.1f", percentComplete))% (\(String(format: "%.1f", loadedDuration))s / \(String(format: "%.1f", expectedDuration))s)")
            }
            await self.onProgressUpdate?(progress)
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task {
            if await self.configuration.enableDebugLogging {
                logger.info("Download finished, processing file")
            }
            await self.handleDownloadFinished(task: assetDownloadTask, location: location)
        }
    }
    
    private func handleDownloadFinished(task: AVAssetDownloadTask, location: URL) {
        guard var state = downloadStates[task] else {
            if configuration.enableDebugLogging {
                logger.warning("No download state found for task")
            }
            return
        }
        
        if configuration.enableDebugLogging {
            logger.info("Updating state with download location")
        }
        
        // Update state with download location
        state.downloadLocation = location
        downloadStates[task] = state
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task {
            await self.handleTaskCompletion(task: task, error: error)
        }
    }
    
    private func handleTaskCompletion(task: URLSessionTask, error: Error?) async {
        guard let assetDownloadTask = task as? AVAssetDownloadTask else {
            if configuration.enableDebugLogging {
                logger.warning("Completed task is not an asset download task")
            }
            return
        }
        
        guard let state = downloadStates.removeValue(forKey: assetDownloadTask) else {
            if configuration.enableDebugLogging {
                logger.warning("No state found for completed task")
            }
            return
        }
        
        if configuration.enableDebugLogging {
            logger.info("Processing completed download")
        }
        
        // Handle error
        if let error = error {
            logger.error("Download failed: \(error.localizedDescription)")
            state.continuation.resume(throwing: error)
            return
        }
        
        // Process successful download
        guard let downloadLocation = state.downloadLocation else {
            logger.error("Download location not found in state")
            state.continuation.resume(throwing: HLSAssetError.downloadLocationNotFound)
            return
        }
        
        if configuration.enableDebugLogging {
            logger.info("Moving file from temporary location to cache")
        }
        
        do {
            // Store in cache
            let finalURL = try await cacheManager.storeAsset(
                from: downloadLocation,
                for: state.sourceURL
            )
            
            logger.info("Download complete, asset cached successfully")
            
            // Resume continuation with final URL
            state.continuation.resume(returning: finalURL)
            
        } catch {
            logger.error("Failed to cache asset: \(error.localizedDescription)")
            state.continuation.resume(throwing: HLSAssetError.failedToMoveAsset(underlying: error))
        }
    }
}
