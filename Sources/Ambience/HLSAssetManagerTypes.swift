//
//  HLSAssetManagerTypes.swift
//  Ambience
//
//  Created by Shuhari on 2024/11/23.
//  Copyright © 2024 Shuhari. All rights reserved.
//

import Foundation
import AVFoundation

// MARK: - Error Types

/// Errors that can occur during HLS asset downloading and caching operations
public enum HLSAssetError: LocalizedError {
    case failedToLoadVariants(underlying: Error)
    case noVariantsFound
    case failedToCreateDownloadTask
    case downloadLocationNotFound
    case failedToMoveAsset(underlying: Error)
    case invalidCacheConfiguration
    
    public var errorDescription: String? {
        switch self {
        case .failedToLoadVariants(let error):
            return "Failed to load video variants: \(error.localizedDescription)"
        case .noVariantsFound:
            return "No video variants available"
        case .failedToCreateDownloadTask:
            return "Failed to create download task"
        case .downloadLocationNotFound:
            return "Download location not found"
        case .failedToMoveAsset(let error):
            return "Failed to move downloaded asset: \(error.localizedDescription)"
        case .invalidCacheConfiguration:
            return "Invalid cache configuration"
        }
    }
}

// MARK: - Download Progress

/// Represents the download progress of an HLS asset
public struct DownloadProgress {
    /// The URL of the asset being downloaded
    public let url: URL
    
    /// Completion percentage (0.0 to 100.0)
    public let percentComplete: Double
    
    /// Duration of content already downloaded (in seconds)
    public let loadedDuration: TimeInterval
    
    /// Expected total duration of the asset (in seconds)
    public let expectedDuration: TimeInterval
    
    public init(url: URL, percentComplete: Double, loadedDuration: TimeInterval, expectedDuration: TimeInterval) {
        self.url = url
        self.percentComplete = percentComplete
        self.loadedDuration = loadedDuration
        self.expectedDuration = expectedDuration
    }
}

// MARK: - Configuration

/// Configuration options for HLS asset downloads and caching
public struct HLSAssetConfiguration {
    /// Maximum number of cached assets before LRU eviction occurs (default: 100)
    public var cacheLimit: Int
    
    /// Target bitrate for video quality selection in bits per second (default: 300,000)
    public var targetBitrate: Double
    
    /// Enable detailed debug logging (default: false)
    public var enableDebugLogging: Bool
    
    public init(
        cacheLimit: Int = 100,
        targetBitrate: Double = 300_000,
        enableDebugLogging: Bool = false
    ) {
        self.cacheLimit = cacheLimit
        self.targetBitrate = targetBitrate
        self.enableDebugLogging = enableDebugLogging
    }
    
    /// Validates the configuration parameters
    var isValid: Bool {
        cacheLimit >= 0 && targetBitrate >= 0
    }
}

// MARK: - Internal Types

/// Metadata information for a cached asset
struct AssetMetadata: Codable {
    let localFilename: String
    let creationDate: Date
    let sourceURL: String?
    
    init(localFilename: String, creationDate: Date, sourceURL: String? = nil) {
        self.localFilename = localFilename
        self.creationDate = creationDate
        self.sourceURL = sourceURL
    }
}

/// Internal state tracking for an ongoing download task
struct DownloadState {
    let task: AVAssetDownloadTask
    let continuation: CheckedContinuation<URL, Error>
    let sourceURL: URL
    let hlsURL: URL
    var downloadLocation: URL?
    var destinationURL: URL?
}

