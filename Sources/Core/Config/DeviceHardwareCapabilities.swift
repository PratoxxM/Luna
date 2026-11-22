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
    public let sessionCacheByteBudget: Int
    public let sessionCacheFreeReserveBytes: Int
    public let defaultLowResUpscaleEnabled: Bool

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
            self.sessionCacheByteBudget = 3 * 1_073_741_824
            self.sessionCacheFreeReserveBytes = 4 * 1_073_741_824
            self.defaultLowResUpscaleEnabled = true
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
            self.sessionCacheByteBudget = 1_073_741_824
            self.sessionCacheFreeReserveBytes = 1_536 * 1_048_576
            self.defaultLowResUpscaleEnabled = false
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

    public func retainsSessionCacheAfterStop(availableMemoryBytes: UInt64) -> Bool {
        switch tier {
        case .high2026:
            return availableMemoryBytes >= 1_000 * 1_048_576
        case .standard:
            return false
        }
    }

    public func forwardBufferSegments(availableMemoryBytes: UInt64) -> Int {
        switch tier {
        case .high2026:
            if availableMemoryBytes >= 1_500 * 1_048_576 {
                return 45
            }
            if availableMemoryBytes >= 700 * 1_048_576 {
                return 24
            }
            return 12
        case .standard:
            return availableMemoryBytes >= 550 * 1_048_576 ? 12 : 8
        }
    }

    public func maxConcurrentSourceRequests(
        isFastLocalTier: Bool,
        isSameOrigin: Bool,
        serverConfigured: Int?
    ) -> Int {
        if let serverConfigured, serverConfigured <= 1 {
            return max(1, serverConfigured)
        }
        let base = serverConfigured ?? 2
        switch tier {
        case .high2026:
            if isFastLocalTier {
                return max(base, 8)
            }
            if isSameOrigin {
                return max(base, 4)
            }
            return base
        case .standard:
            if isFastLocalTier {
                return max(base, 6)
            }
            if isSameOrigin {
                return max(base, 3)
            }
            return base
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

    public static let supportsHardwareAV1: Bool = {
        #if canImport(VideoToolbox) && canImport(CoreMedia)
        #if os(macOS)
        if #available(macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1)
        }
        #endif
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        #else
        return false
        #endif
    }()

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

extension TvCandidateInfo {
    private static let nonHEVCCodecs: Set<String> = [
        "av1", "av01", "h264", "avc", "avc1", "x264",
        "vp9", "vp09", "vp8", "mpeg2", "mpeg2video", "vc1", "wmv3", "theora",
    ]

    private static let softwareOnlyCodecs: Set<String> = [
        "vp9", "vp09", "vp8", "mpeg2", "mpeg2video", "vc1", "wmv3", "theora",
    ]

    public var normalizedVideoCodec: String {
        (videoCodec ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True only when the candidate can plausibly carry an HEVC Dolby Vision Profile 7 FEL layer.
    /// Prevents non-HEVC codecs (such as A19 hardware AV1 / AV1 DV P10), single-layer DV P5/P8,
    /// and plain HDR10/HLG/SDR streams from requesting dual-layer FEL probing.
    public var canCarryDualLayerDolbyVision: Bool {
        if !allowsDualLayerDolbyVisionWhenForced {
            return false
        }
        let layer = (dvEnhancementLayer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if layer == "MEL" || layer == "NONE" {
            return false
        }
        if dvProfile == 7 || layer == "FEL" {
            return true
        }
        if let range = videoRangeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !range.isEmpty,
           range != "unknown" {
            return range.contains("dv") || range.contains("dolby")
        }
        return true
    }

    /// Guards even `.forceOn` from enabling HEVC Profile 7 dual-layer on streams whose codec or
    /// Dolby Vision profile makes an HEVC FEL enhancement layer physically impossible.
    public var allowsDualLayerDolbyVisionWhenForced: Bool {
        let codec = normalizedVideoCodec
        if !codec.isEmpty, Self.nonHEVCCodecs.contains(codec) {
            return false
        }
        if let dvProfile, dvProfile != 7 {
            return false
        }
        return true
    }

    public func requiresSoftwareVideoDecode(
        supportsHardwareAV1: Bool = DeviceHardwareCapabilities.supportsHardwareAV1
    ) -> Bool {
        let codec = normalizedVideoCodec
        if codec == "av1" || codec == "av01" {
            return !supportsHardwareAV1
        }
        return Self.softwareOnlyCodecs.contains(codec)
    }

    public var isLikelyLowResolutionSDRForUpscale: Bool {
        if dvProfile != nil {
            return false
        }
        if let range = videoRangeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !range.isEmpty,
           range != "sdr",
           range != "unknown" {
            return false
        }
        let res = (resolution ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1080p", "720p", "576p", "480p", "sd", "hd"].contains(res)
    }
}
