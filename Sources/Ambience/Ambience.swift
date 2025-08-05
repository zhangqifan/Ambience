//
//  AmbienceService.swift
//  Ambience
//
//  Created by Shuhari on 2024/10/12.
//  Copyright © 2024 Shuhari. All rights reserved.
//
//  This file is part of the Ambience package.
//
//  Description:
//  AmbienceService provides functionality for fetching and processing ambience
//  artwork assets associated with Apple Music items. It includes methods for
//  URL adjustment, HTML content fetching, and ambience artwork URL extraction.

import Foundation
import Kanna
import MusicKit

/// Main class for handling Ambience-related operations
public enum AmbienceService {
    /// set the cache limit of ambience assets
    public static var cacheLimit = 100
    /// set the target bitrate for ambience assets
    public static var targetBitrate:Double = 300_000
    /// Errors that can occur during ambience artwork download
    public enum AmbienceError: Error {
        case invalidURL
        case invalidHTMLContent
        case noAmbienceArtworkFound
        case networkError
        case redirectedToHomepage
    }
    
    /// Policy for choosing which storefront to use when fetching ambience assets
    public enum StorefrontChoosePolicy {
        /// Use only the account's storefront (original URL without region adjustment)
        case followAccount
        /// Use only the device's region storefront (URL adjusted to match device region)
        case followRegion
        /// Try both storefronts with fallback mechanism, controlled by `regionFirst` property
        case tryBoth
    }
    
    /// If true, the region-adjusted URL will be tried first, otherwise the account URL will be tried first
    private static var regionFirst: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "Ambience_regionFirst")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Ambience_regionFirst")
        }
    }
    
    /// Fetches the ambience asset configuration file URL for a given music item source URL
    /// - Parameters:
    ///   - musicItemSourceURL: The URL of the music item source
    ///   - storefrontPolicy: The policy for choosing which storefront to use (default: .tryBoth)
    /// - Returns: The URL of the ambience asset configuration file
    /// - Throws: `AmbienceError` if any error occurs during the process
    ///
    /// - Note: The `storefrontPolicy` parameter is crucial in certain scenarios where the user's physical location
    ///   doesn't match their Apple Music subscription region. For example:
    ///
    ///   A user located in mainland China might have an Apple Music subscription registered in the United States.
    ///   In this case, when trying to access certain playlists (especially Apple Music's official curated playlists
    ///   like Heavy Rotation Mix), the default behavior might fail to retrieve the Ambience content.
    ///
    ///   The `regionFirst` property controls the priority when using `.tryBoth` policy:
    ///   - If `regionFirst` is `true`, it tries region-adjusted URL first, then falls back to account URL
    ///   - If `regionFirst` is `false`, it tries account URL first, then falls back to region-adjusted URL
    ///
    ///   Example usage:
    ///   ```
    ///   // Try both account and region storefronts (default behavior)
    ///   let ambienceURL = try await AmbienceService.fetchAmbienceAsset(from: musicItemURL)
    ///
    ///   // Only use account storefront
    ///   let accountOnlyURL = try await AmbienceService.fetchAmbienceAsset(from: musicItemURL, storefrontPolicy: .followAccount)
    ///
    ///   // Only use region storefront
    ///   let regionOnlyURL = try await AmbienceService.fetchAmbienceAsset(from: musicItemURL, storefrontPolicy: .followRegion)
    ///   ```
    public static func fetchAmbienceAsset(
        from musicItemSourceURL: URL,
        storefrontPolicy: StorefrontChoosePolicy = .tryBoth
    ) async throws -> URL {
        let adjustedURL = try await URLAdjuster.adjustURLForRegion(musicItemSourceURL)
        switch storefrontPolicy {
        case .followAccount:
            return try await HLSAssetManager.shared.getAsset(from: musicItemSourceURL)
        case .followRegion:
            return try await HLSAssetManager.shared.getAsset(from: adjustedURL)
        case .tryBoth:
            if regionFirst {
                do {
                    return try await HLSAssetManager.shared.getAsset(from: adjustedURL)
                } catch AmbienceError.redirectedToHomepage {
                    let res = try await HLSAssetManager.shared.getAsset(from: musicItemSourceURL)
                    regionFirst = false
                    return res
                }
            } else {
                do {
                    return try await HLSAssetManager.shared.getAsset(from: musicItemSourceURL)
                } catch AmbienceError.redirectedToHomepage {
                    let res = try await HLSAssetManager.shared.getAsset(from: adjustedURL)
                    regionFirst = true
                    return res
                }
            }
        }
    }
}

/// Struct responsible for adjusting URLs based on region
private enum URLAdjuster {
    
    /// Adjusts the given URL to match the device's region if necessary
    /// - Parameter url: The original URL to adjust
    /// - Returns: An adjusted URL that matches the device's region
    /// - Throws: An error if the URL adjustment fails
    static func adjustURLForRegion(_ url: URL) async throws -> URL {
        let deviceRegionIdentifier: String?
        if #available(iOS 16, *) {
            deviceRegionIdentifier = Locale.current.region?.identifier.lowercased()
        } else {
            deviceRegionIdentifier = Locale.current.regionCode?.lowercased()
        }
        let amCode = try await MusicDataRequest.currentCountryCode
        
        guard let deviceRegionIdentifier = deviceRegionIdentifier, amCode != deviceRegionIdentifier else {
            return url
        }
        
        return try replaceStorefront(in: url, from: amCode, to: deviceRegionIdentifier)
    }
    
    /// Replaces the storefront in the given URL
    /// - Parameters:
    ///   - url: The original URL
    ///   - originalStorefront: The current storefront code in the URL
    ///   - newStorefront: The new storefront code to replace with
    /// - Returns: A URL with the updated storefront
    /// - Throws: An error if the URL manipulation fails
    private static func replaceStorefront(
        in url: URL,
        from originalStorefront: String,
        to newStorefront: String?
    ) throws -> URL {
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AmbienceService.AmbienceError.invalidURL
        }
        
        guard let newStorefront = newStorefront else {
            return url
        }
        
        var pathComponents = url.pathComponents
        pathComponents.removeFirst()
        
        if let index = pathComponents.firstIndex(of: originalStorefront) {
            pathComponents[index] = newStorefront
        }
        
        urlComponents.path = "/" + pathComponents.joined(separator: "/")
        
        guard let adjustedURL = urlComponents.url else {
            throw AmbienceService.AmbienceError.invalidURL
        }
        
        return adjustedURL
    }
}

/// Struct responsible for fetching HTML content
enum HTMLFetcher {
    
    private class RedirectDetector: NSObject, URLSessionTaskDelegate {
        var hasRedirected = false
        
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            if response.statusCode == 302 {
                hasRedirected = true
                completionHandler(nil)
            } else {
                completionHandler(request)
            }
        }
    }
    
    /// Fetches HTML content from a given URL
    /// - Parameter url: The URL to fetch HTML content from
    /// - Returns: The HTML content as a string
    /// - Throws: An error if the network request fails or the response is invalid
    static func fetchHTMLContent(from url: URL) async throws -> String {
        let redirectDetector = RedirectDetector()
        let session = URLSession(configuration: .default, delegate: redirectDetector, delegateQueue: nil)
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AmbienceService.AmbienceError.networkError
        }
        
        if redirectDetector.hasRedirected {
            throw AmbienceService.AmbienceError.redirectedToHomepage
        }
        
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw AmbienceService.AmbienceError.networkError
        }
        
        guard let htmlString = String(data: data, encoding: .utf8), !htmlString.isEmpty else {
            throw AmbienceService.AmbienceError.invalidHTMLContent
        }
        
        return htmlString
    }
}

/// Struct responsible for extracting ambience artwork URL from HTML content
enum AmbienceArtworkExtractor {
    /// Extracts the ambience artwork URL from the given HTML content
    /// - Parameter htmlContent: The HTML content to extract the URL from
    /// - Returns: The URL of the ambience artwork
    /// - Throws: An error if the ambience artwork URL cannot be found or is invalid
    static func extractAmbienceArtworkURL(from htmlContent: String) throws -> URL {
        let keyword = "amp-ambient-video"
        let ampAmbientVideoTagStart = "<" + keyword
        let ampAmbientVideoTagEnd = "</" + keyword + ">"
        
        guard let startRange = htmlContent.range(of: ampAmbientVideoTagStart),
              let endRange = htmlContent.range(of: ampAmbientVideoTagEnd)
        else {
            throw AmbienceService.AmbienceError.noAmbienceArtworkFound
        }
        
        let content = htmlContent[startRange.lowerBound ..< endRange.upperBound]
        let html = String(content)
        
        let doc = try HTML(html: html, encoding: .utf8)
        
        guard let source = doc.xpath("//" + keyword).first?["src"],
              !source.isEmpty,
              let url = URL(string: source)
        else {
            throw AmbienceService.AmbienceError.noAmbienceArtworkFound
        }
        
        return url
    }
}
