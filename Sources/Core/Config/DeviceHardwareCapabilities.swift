import Foundation
#if canImport(VideoToolbox) && canImport(CoreMedia)
import CoreMedia
import VideoToolbox
#endif
#if canImport(Darwin) && (os(tvOS) || os(iOS))
import os
#endif

public enum DeviceMemoryTier: String, Sendable, Equatable {
    case standard
    case high2026
}

/// Adaptive memory, concurrency, and prefetch profile distinguishing 3–4 GB Apple TV 4K
/// models (`standard`) from the 8 GB / A19 / Wi-Fi 7 / 128 GB Apple TV 4K (`high2026`).
public struct DeviceMemoryProfile: Sendable, Equatable {
    public let tier: DeviceMemoryTier
    public let artworkMemoryBytes: Int
    public let artworkMemoryCountLimit: Int
    public let artworkDiskMaxBytes: Int64
    public let artworkDiskTrimWriteInterval: Int
    public let maxConcurrentDecodes: Int
    public let apiConnectionsPerHost: Int
    public let artworkConnectionsPerHost: Int
    public let externalArtworkConnectionsPerHost: Int
    public let catalogPageSize: Int
    public let libraryPageSize: Int
    public let catalogCacheMaxEntries: Int
    public let libraryCacheMaxEntries: Int
    public let itemDetailCacheMaxEntries: Int
    public let scrollPrefetchCardWindow: Int
    public let enableBackgroundCatalogMetadataWarmup: Bool
    public let playbackMemoryShedFloorBytes: UInt64

    public init(
        physicalMemoryBytes: UInt64,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) {
        let isHigh = DeviceHardwareCapabilities.isHighMemory(physicalMemoryBytes: physicalMemoryBytes)
        let cores = max(2, activeProcessorCount)
        if isHigh {
            self.tier = .high2026
            self.artworkMemoryBytes = 384 * 1024 * 1024
            self.artworkMemoryCountLimit = 1_400
            self.artworkDiskMaxBytes = 512 * 1024 * 1024
            self.artworkDiskTrimWriteInterval = 64
            self.maxConcurrentDecodes = min(8, max(6, cores + 2))
            self.apiConnectionsPerHost = 12
            self.artworkConnectionsPerHost = 16
            self.externalArtworkConnectionsPerHost = 16
            self.catalogPageSize = 48
            self.libraryPageSize = 60
            self.catalogCacheMaxEntries = 64
            self.libraryCacheMaxEntries = 36
            self.itemDetailCacheMaxEntries = 32
            self.scrollPrefetchCardWindow = 18
            self.enableBackgroundCatalogMetadataWarmup = true
            self.playbackMemoryShedFloorBytes = 1_500 * 1024 * 1024
        } else {
            self.tier = .standard
            self.artworkMemoryBytes = 112 * 1024 * 1024
            self.artworkMemoryCountLimit = 420
            self.artworkDiskMaxBytes = 160 * 1024 * 1024
            self.artworkDiskTrimWriteInterval = 32
            self.maxConcurrentDecodes = 4
            self.apiConnectionsPerHost = 8
            self.artworkConnectionsPerHost = 8
            self.externalArtworkConnectionsPerHost = 8
            self.catalogPageSize = 30
            self.libraryPageSize = 36
            self.catalogCacheMaxEntries = 16
            self.libraryCacheMaxEntries = 12
            self.itemDetailCacheMaxEntries = 8
            self.scrollPrefetchCardWindow = 6
            self.enableBackgroundCatalogMetadataWarmup = false
            self.playbackMemoryShedFloorBytes = 900 * 1024 * 1024
        }
    }

    public func prewarmByteBudget(availableMemoryBytes: UInt64) -> Int {
        switch tier {
        case .high2026:
            if availableMemoryBytes > 1_400 * 1024 * 1024 {
                return 48 * 1024 * 1024
            }
            if availableMemoryBytes > 640 * 1024 * 1024 {
                return 28 * 1024 * 1024
            }
            return 0
        case .standard:
            return availableMemoryBytes > 512 * 1024 * 1024 ? (8 * 1024 * 1024) : 0
        }
    }

    public static let current = DeviceMemoryProfile(
        physicalMemoryBytes: DeviceHardwareCapabilities.physicalMemoryBytes,
        activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
    )
}

/// Runtime hardware capability detection (RAM tier & hardware AV1 decoding).
/// Shared across Darwin tvOS runtime and Linux unit tests without UIKit/SwiftUI coupling.
public enum DeviceHardwareCapabilities: Sendable {
    public static let highMemoryThresholdBytes: UInt64 = 6 * 1_073_741_824

    public static var physicalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    public static var physicalMemoryGB: Int {
        roundedGigabytes(for: physicalMemoryBytes)
    }

    public static var isHighMemoryDevice: Bool {
        isHighMemory(physicalMemoryBytes: physicalMemoryBytes)
    }

    public static var memoryProfile: DeviceMemoryProfile {
        DeviceMemoryProfile.current
    }

    public static var supportsHardwareAV1: Bool {
        #if canImport(VideoToolbox) && canImport(CoreMedia)
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        #else
        return false
        #endif
    }

    public static func roundedGigabytes(for physicalMemoryBytes: UInt64) -> Int {
        max(1, Int((Double(physicalMemoryBytes) / 1_073_741_824.0).rounded()))
    }

    public static func isHighMemory(physicalMemoryBytes: UInt64) -> Bool {
        physicalMemoryBytes >= highMemoryThresholdBytes
    }

    public static func availableMemoryBytes() -> UInt64 {
        #if canImport(Darwin) && (os(tvOS) || os(iOS))
        let avail = os_proc_available_memory()
        if avail > 0 {
            return UInt64(avail)
        }
        #endif
        return physicalMemoryBytes / 2
    }
}
