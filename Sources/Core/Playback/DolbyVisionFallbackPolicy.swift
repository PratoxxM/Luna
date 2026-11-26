import Foundation

/// Pure, non-isolated telemetry policy detecting sustained frame drops on Dolby Vision Profile 7 FEL
/// software playback so the player can surface a 1-tap `Bytt til HDR10-baselag` action.
public struct DolbyVisionFallbackPolicy: Equatable, Sendable {
    public static let defaultDropDeltaThreshold: Int = 15
    public static let defaultAbsoluteDropThreshold: Int = 24

    public private(set) var shouldSuggestBaseLayer: Bool = false
    private var baselineDroppedFrames: Int?

    public init() {}

    public mutating func recordTelemetrySample(
        droppedFrames: Int,
        isProfile7FEL: Bool,
        isBaseLayerForced: Bool
    ) -> Bool {
        guard isProfile7FEL, !isBaseLayerForced else {
            shouldSuggestBaseLayer = false
            baselineDroppedFrames = nil
            return false
        }

        let safeDrops = max(0, droppedFrames)
        if let baseline = baselineDroppedFrames {
            let delta = safeDrops - baseline
            if delta >= Self.defaultDropDeltaThreshold || safeDrops >= Self.defaultAbsoluteDropThreshold {
                shouldSuggestBaseLayer = true
            }
        } else if safeDrops >= Self.defaultAbsoluteDropThreshold {
            baselineDroppedFrames = 0
            shouldSuggestBaseLayer = true
        } else {
            baselineDroppedFrames = safeDrops
        }

        return shouldSuggestBaseLayer
    }

    public mutating func reset() {
        shouldSuggestBaseLayer = false
        baselineDroppedFrames = nil
    }
}
