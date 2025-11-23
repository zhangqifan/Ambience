//
//  VariantSelector.swift
//  Ambience
//
//  Created by Shuhari on 2024/11/23.
//  Copyright © 2024 Shuhari. All rights reserved.
//

import Foundation
import AVFoundation
import os

/// Selects the optimal video variant based on bitrate requirements
struct VariantSelector {
    private let logger: Logger
    private let enableDebugLogging: Bool
    
    init(logger: Logger, enableDebugLogging: Bool) {
        self.logger = logger
        self.enableDebugLogging = enableDebugLogging
    }
    
    /// Selects the best variant from available variants based on target bitrate
    /// - Parameters:
    ///   - variants: Available video variants
    ///   - targetBitrate: Target bitrate in bits per second
    /// - Returns: The best matching variant, or the lowest bitrate variant if none meet the target
    func selectBestVariant(from variants: [AVAssetVariant], targetBitrate: Double) -> AVAssetVariant? {
        guard !variants.isEmpty else {
            return nil
        }
        
        if enableDebugLogging {
            logAvailableVariants(variants)
        }
        
        // Find the variant with lowest bitrate that meets or exceeds target
        let bestVariant = variants
            .sorted { ($0.averageBitRate ?? 0) < ($1.averageBitRate ?? 0) }
            .first { ($0.averageBitRate ?? 0) >= targetBitrate }
        
        if let selected = bestVariant {
            if enableDebugLogging {
                logger.info("Selected variant with bitrate: \(selected.averageBitRate ?? 0) bps")
            }
        } else {
            if enableDebugLogging {
                logger.info("No variant meets target bitrate \(Int(targetBitrate)), using lowest available")
            }
            return variants.min(by: { ($0.averageBitRate ?? 0) < ($1.averageBitRate ?? 0) })
        }
        
        return bestVariant
    }
    
    private func logAvailableVariants(_ variants: [AVAssetVariant]) {
        logger.info("Available variants: \(variants.count)")
        for (index, variant) in variants.enumerated() {
            let avgBitrate = variant.averageBitRate ?? 0
            let peakBitrate = variant.peakBitRate ?? 0
            logger.info("  [\(index)] avg: \(formatBitrate(avgBitrate)), peak: \(formatBitrate(peakBitrate))")
        }
    }
    
    private func formatBitrate(_ bitrate: Double) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else {
            return String(format: "%.0f Kbps", bitrate / 1_000)
        }
    }
}

