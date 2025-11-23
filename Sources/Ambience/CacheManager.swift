//
//  CacheManager.swift
//  Ambience
//
//  Created by Shuhari on 2024/11/23.
//  Copyright © 2024 Shuhari. All rights reserved.
//

import Foundation
import os

/// Manages caching of HLS assets with LRU (Least Recently Used) eviction policy
actor CacheManager {
    private let cacheDirectory: URL
    private let metadataURL: URL
    private let cacheLimit: Int
    private let logger: Logger
    private let filenameStrategy: FilenameStrategy
    private let enableDebugLogging: Bool
    
    private var assetMetadata: [String: AssetMetadata] = [:]
    
    init(cacheDirectory: URL, cacheLimit: Int, logger: Logger, enableDebugLogging: Bool) {
        self.cacheDirectory = cacheDirectory
        self.metadataURL = cacheDirectory.appendingPathComponent("metadata.json")
        self.cacheLimit = cacheLimit
        self.logger = logger
        self.enableDebugLogging = enableDebugLogging
        self.filenameStrategy = FilenameStrategy(logger: logger, enableDebugLogging: enableDebugLogging)
        
        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        loadMetadata()
    }
    
    // MARK: - Public Methods
    
    /// Returns the local URL for a cached asset, if it exists
    func getCachedAssetURL(for sourceURL: URL) -> URL? {
        let filename = filenameStrategy.generateFilename(for: sourceURL)
        
        guard assetMetadata[filename] != nil else {
            return nil
        }
        
        let localURL = cacheDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            // Clean up stale metadata
            assetMetadata.removeValue(forKey: filename)
            saveMetadata()
            return nil
        }
        
        return localURL
    }
    
    /// Stores a downloaded asset in the cache directory
    /// - Parameters:
    ///   - temporaryLocation: The temporary location where the downloaded file currently resides
    ///   - sourceURL: The original source URL of the music item
    /// - Returns: The final URL where the asset is cached
    /// - Throws: An error if the file operation fails
    func storeAsset(from temporaryLocation: URL, for sourceURL: URL) throws -> URL {
        if enableDebugLogging {
            logger.info("Storing asset from temporary location")
            logger.info("  Source: \(temporaryLocation.path)")
            logger.info("  Origin URL: \(sourceURL.lastPathComponent)")
        }
        
        let filename = filenameStrategy.generateFilename(for: sourceURL)
        let destinationURL = cacheDirectory.appendingPathComponent(filename)
        
        if enableDebugLogging {
            logger.info("  Destination: \(destinationURL.path)")
        }
        
        // Check if source exists
        guard FileManager.default.fileExists(atPath: temporaryLocation.path) else {
            logger.error("Source file does not exist at: \(temporaryLocation.path)")
            throw NSError(domain: "CacheManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Source file not found"])
        }
        
        // Remove old file if exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if enableDebugLogging {
                logger.info("Removing existing file at destination")
            }
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        // Move file to cache
        do {
            try FileManager.default.moveItem(at: temporaryLocation, to: destinationURL)
            if enableDebugLogging {
                logger.info("File moved successfully to cache")
            }
        } catch {
            logger.error("Failed to move file: \(error.localizedDescription)")
            throw error
        }
        
        // Verify file exists at destination
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            logger.error("File not found at destination after move operation")
            throw NSError(domain: "CacheManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "File verification failed"])
        }
        
        // Update metadata
        let metadata = AssetMetadata(
            localFilename: filename,
            creationDate: Date(),
            sourceURL: sourceURL.absoluteString
        )
        assetMetadata[filename] = metadata
        
        if enableDebugLogging {
            logger.info("Metadata updated for cached asset")
        }
        
        // Enforce cache limit
        enforceCacheLimit()
        
        // Save metadata
        saveMetadata()
        
        logger.info("Asset successfully cached: \(filename)")
        return destinationURL
    }
    
    /// Returns cache statistics
    /// - Returns: A tuple containing current cache count and configured limit
    func getCacheStats() -> (count: Int, limit: Int) {
        return (assetMetadata.count, cacheLimit)
    }
    
    /// Clears all cached assets from disk and metadata
    /// - Throws: An error if file removal fails
    func clearCache() throws {
        for metadata in assetMetadata.values {
            let url = cacheDirectory.appendingPathComponent(metadata.localFilename)
            try? FileManager.default.removeItem(at: url)
        }
        assetMetadata.removeAll()
        saveMetadata()
        logger.info("Cache cleared successfully")
    }
    
    // MARK: - Private Methods
    
    /// Loads cached metadata from disk
    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: AssetMetadata].self, from: data)
        else {
            if enableDebugLogging {
                logger.info("No existing cache metadata found")
            }
            assetMetadata = [:]
            return
        }
        
        assetMetadata = decoded
        if enableDebugLogging {
            logger.info("Loaded cache metadata: \(self.assetMetadata.count) items")
        }
    }
    
    /// Persists metadata to disk
    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(assetMetadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            logger.error("Failed to save cache metadata: \(error.localizedDescription)")
        }
    }
    
    /// Enforces the cache size limit using LRU eviction policy
    private func enforceCacheLimit() {
        guard assetMetadata.count > cacheLimit else { return }
        
        // Sort by creation date to identify least recently used assets
        let sortedAssets = assetMetadata.values.sorted { $0.creationDate < $1.creationDate }
        let assetsToRemoveCount = assetMetadata.count - cacheLimit
        let assetsToRemove = sortedAssets.prefix(assetsToRemoveCount)
        
        for asset in assetsToRemove {
            let url = cacheDirectory.appendingPathComponent(asset.localFilename)
            try? FileManager.default.removeItem(at: url)
            assetMetadata.removeValue(forKey: asset.localFilename)
            if enableDebugLogging {
                logger.info("Evicted old asset: \(asset.localFilename)")
            }
        }
    }
}

