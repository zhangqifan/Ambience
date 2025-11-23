//
//  FilenameStrategy.swift
//  Ambience
//
//  Created by Shuhari on 2024/11/23.
//  Copyright © 2024 Shuhari. All rights reserved.
//

import Foundation
import os

/// Generates safe and consistent filenames for cached assets based on source URLs
struct FilenameStrategy {
    private let logger: Logger
    private let enableDebugLogging: Bool
    private static let fileExtension = ".movpkg"
    
    init(logger: Logger, enableDebugLogging: Bool) {
        self.logger = logger
        self.enableDebugLogging = enableDebugLogging
    }
    
    /// Generates a safe filename for the given URL
    /// - Parameter url: The source URL of the music item
    /// - Returns: A safe filename with `.movpkg` extension
    /// - Note: Attempts to extract album or playlist IDs for better cache hit rates
    func generateFilename(for url: URL) -> String {
        let urlString = url.absoluteString
        
        // Try to extract album ID
        if let albumID = extractAlbumID(from: urlString) {
            if enableDebugLogging {
                logger.debug("Using album ID for filename: \(albumID)")
            }
            return albumID + Self.fileExtension
        }
        
        // Try to extract playlist ID
        if let playlistID = extractPlaylistID(from: urlString) {
            if enableDebugLogging {
                logger.debug("Using playlist ID for filename: \(playlistID)")
            }
            return playlistID + Self.fileExtension
        }
        
        // Fallback to sanitized URL
        if enableDebugLogging {
            logger.debug("Using sanitized URL for filename")
        }
        return sanitizeURL(urlString) + Self.fileExtension
    }
    
    // MARK: - Private Methods
    
    /// Extracts album ID from Apple Music URL
    /// - Parameter urlString: The URL string to parse
    /// - Returns: The album ID if found, nil otherwise
    /// - Example: `https://music.apple.com/cn/album/lover/1468058165` → `1468058165`
    private func extractAlbumID(from urlString: String) -> String? {
        guard let match = urlString.range(of: #"album/[^/]+/(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let path = urlString[match]
        return path.split(separator: "/").last.map(String.init)
    }
    
    /// Extracts playlist ID from Apple Music URL
    /// - Parameter urlString: The URL string to parse
    /// - Returns: The playlist ID if found, nil otherwise
    /// - Example: `https://music.apple.com/cn/playlist/name/pl.abc123` → `abc123`
    private func extractPlaylistID(from urlString: String) -> String? {
        guard let match = urlString.range(of: "pl\\.([a-zA-Z0-9]+)", options: .regularExpression) else {
            return nil
        }
        let path = urlString[match]
        return path.split(separator: ".").last.map(String.init)
    }
    
    /// Sanitizes a URL string to create a valid and safe filename
    /// - Parameter urlString: The URL string to sanitize
    /// - Returns: A sanitized string suitable for use as a filename
    private func sanitizeURL(_ urlString: String) -> String {
        guard urlString.hasPrefix("https://music.apple.com") else {
            // For non-Apple Music URLs, use a hash
            return String(urlString.hashValue)
        }
        
        return urlString
            .replacingOccurrences(of: "https://music.apple.com", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_")
            .prefix(100)  // Limit length to prevent filesystem issues
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

