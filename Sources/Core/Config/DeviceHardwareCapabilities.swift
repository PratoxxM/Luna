import Foundation
#if canImport(VideoToolbox) && canImport(CoreMedia)
import CoreMedia
import VideoToolbox
#endif
#if canImport(Darwin) && (os(tvOS) || os(iOS))
import os
#endif

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
