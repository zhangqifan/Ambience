import Foundation
import AVFoundation
import CryptoKit
import os

/// Manages downloading and caching of HLS assets.
/// This class is a singleton that handles the entire lifecycle of HLS video assets,
/// including downloading, storing with a predictable filename, and enforcing a cache limit.
class HLSAssetManager: NSObject, ObservableObject {
    static let shared = HLSAssetManager()

    // MARK: - Published Properties for UI
    @Published var isDownloading = false
    @Published var currentError: String?

    // MARK: - Private Properties
    private var downloadSession: AVAssetDownloadURLSession!
    private let cacheLimit = 100
    private let targetBitrate:Double = 800_000 // 800 kbps, adjust as needed
    private let cacheDirectory: URL
    private let metadataURL: URL
    private var assetMetadata: [String: AssetMetadata] = [:]
    
    // Modern logging
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HLSAssetManager")

    // To prevent re-downloading the same asset concurrently
    private var activeDownloadTasks: [URL: Task<URL, Error>] = [:]
    
    // Delegate callbacks need a way to resume continuations
    private var downloadContinuations: [AVAssetDownloadTask: CheckedContinuation<URL, Error>] = [:]

    private override init() {
        let fileManager = FileManager.default
        // Create a dedicated directory for HLS assets in Caches
        let cacheBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheBaseURL.appendingPathComponent("HLSAssets")
        self.metadataURL = self.cacheDirectory.appendingPathComponent("metadata.json")

        super.init()

        // Ensure the cache directory exists
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        
        loadMetadata()
        
        // Setup background download session
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.ambience.hlsAssetManager")
        self.downloadSession = AVAssetDownloadURLSession(configuration: configuration,
                                                       assetDownloadDelegate: self,
                                                       delegateQueue: OperationQueue.main)
    }

    /// Returns the local URL for a given remote URL if it's already cached.
    func localAssetURL(for remoteURL: URL) -> URL? {
        let filename = safeFilename(for: remoteURL)
        if assetMetadata[remoteURL.absoluteString] != nil {
            let localURL = cacheDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }
        return nil
    }

    /// Downloads an HLS asset from a remote URL and stores it in the cache.
    /// If the asset is already being downloaded, it awaits the result of the existing download.
    func downloadAsset(from remoteURL: URL) async throws -> URL {
        // If already cached, return the local URL immediately.
        if let localURL = localAssetURL(for: remoteURL) {
            Self.logger.info("Cache hit for URL: \(remoteURL.absoluteString)")
            return localURL
        }

        // If a download for this URL is already in progress, await its result.
        if let existingTask = activeDownloadTasks[remoteURL] {
            Self.logger.info("Download already in progress for URL: \(remoteURL.absoluteString). Awaiting result.")
            return try await existingTask.value
        }

        let downloadTask = Task {
            defer {
                // Clean up after the task is complete
                Task { @MainActor in
                    self.activeDownloadTasks[remoteURL] = nil
                    self.isDownloading = false
                }
            }
            Self.logger.info("Cache miss for URL: \(remoteURL.absoluteString). Starting new download.")
            return try await performDownload(from: remoteURL)
        }

        // Store the new task
        await MainActor.run {
            self.isDownloading = true
            self.activeDownloadTasks[remoteURL] = downloadTask
        }

        return try await downloadTask.value
    }
    
    // MARK: - Private Core Logic
    private func performDownload(from remoteURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            Task{
                let asset = AVURLAsset(url: remoteURL)
                
                // Asynchronously load variants to select resolution
                // 异步加载变体信息
                guard let variants = try? await asset.load(.variants) else {return}
                
                guard !variants.isEmpty else {
                    continuation.resume(throwing: NSError(domain: "HLSAssetManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video variants found."]))
                    return
                }
                
                let bestVariant = variants.sorted { left, right in
                    left.averageBitRate ?? 0 < right.averageBitRate ?? 0
                }.first { $0.averageBitRate ?? 0 >= self.targetBitrate }
                
                
                var options: [String: Any]? = nil
                if let variant = bestVariant {
                    options = [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: variant.averageBitRate ?? 0]
                }
                
                guard let task = self.downloadSession.makeAssetDownloadTask(asset: asset,
                                                                            assetTitle: remoteURL.lastPathComponent,
                                                                            assetArtworkData: nil,
                                                                            options: options) else {
                    continuation.resume(throwing: NSError(domain: "HLSAssetManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create download task."]))
                    return
                }
                
                self.downloadContinuations[task] = continuation
                task.resume()
            }
        }
    }
}

// MARK: - AVAssetDownloadDelegate
extension HLSAssetManager: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let continuation = downloadContinuations.removeValue(forKey: assetDownloadTask) else { return }
        
        let remoteURL = assetDownloadTask.urlAsset.url
        let filename = safeFilename(for: remoteURL)
        let destinationURL = cacheDirectory.appendingPathComponent(filename)

        do {
            // Move the downloaded asset from the temp location to our cache directory
            try? FileManager.default.removeItem(at: destinationURL) // Remove old file if it exists
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            Self.logger.info("Successfully downloaded and cached asset from \(remoteURL.absoluteString) to \(destinationURL.path)")
            
            // Update metadata
            let metadata = AssetMetadata(remoteURL: remoteURL.absoluteString,
                                         localFilename: filename,
                                         creationDate: Date())
            addAssetToMetadata(metadata)
            
            continuation.resume(returning: destinationURL)
        } catch {
            Self.logger.error("Failed to move downloaded asset for \(remoteURL.absoluteString). Error: \(error.localizedDescription)")
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let assetDownloadTask = task as? AVAssetDownloadTask,
              let continuation = downloadContinuations.removeValue(forKey: assetDownloadTask) else {
            return
        }

        if let error = error {
            Self.logger.error("Download failed for task \(assetDownloadTask.urlAsset.url.absoluteString) with error: \(error.localizedDescription)")
            continuation.resume(throwing: error)
        }
    }
}


// MARK: - Metadata and Cache Management
private extension HLSAssetManager {
    /// A metadata structure to track cached assets.
    struct AssetMetadata: Codable {
        let remoteURL: String
        let localFilename: String
        let creationDate: Date
    }

    /// Generates a collision-resistant, filesystem-safe filename from a URL.
    /// We use a SHA256 hash of the URL string to ensure a unique and safe name.
    func safeFilename(for url: URL) -> String {
        let hash: SHA256.Digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".movpkg"
    }

    func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let decodedMetadata = try? JSONDecoder().decode([String: AssetMetadata].self, from: data) else {
            Self.logger.info("No existing metadata found. Starting fresh.")
            self.assetMetadata = [:]
            return
        }
        self.assetMetadata = decodedMetadata
        Self.logger.info("Successfully loaded HLS asset metadata for \(self.assetMetadata.count) items.")
    }

    func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(assetMetadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save HLS asset metadata: \(error.localizedDescription)")
        }
    }

    func addAssetToMetadata(_ metadata: AssetMetadata) {
        assetMetadata[metadata.remoteURL] = metadata
        enforceCacheLimit()
        saveMetadata()
    }

    func enforceCacheLimit() {
        guard assetMetadata.count > cacheLimit else { return }

        // Sort by creation date to find the oldest assets
        let sortedAssets = assetMetadata.values.sorted { $0.creationDate < $1.creationDate }
        
        // Number of assets to remove
        let assetsToRemoveCount = assetMetadata.count - cacheLimit
        let assetsToRemove = sortedAssets.prefix(assetsToRemoveCount)

        for asset in assetsToRemove {
            let localURL = cacheDirectory.appendingPathComponent(asset.localFilename)
            try? FileManager.default.removeItem(at: localURL)
            assetMetadata.removeValue(forKey: asset.remoteURL)
            Self.logger.info("Cache limit reached. Removed old asset: \(asset.remoteURL)")
        }
    }
} 
