import Foundation
import Observation

/// Isolated startup & WebSocket resolution progress state observed exclusively by
/// `ResolvingProgressClusterLeafView` so progress ticks never re-render `PlayerContainerView`
/// or `ResolvingCurtainView`'s backdrop/logo hierarchy.
@MainActor
@Observable
public final class PlayerStartupState {
    public var resolveStageLabel: String = "Klargjør avspilling…"
    public var resolvePercent: Int = 12
    public var resolveHeadline: String?
    public private(set) var engineStartupPercentBucket: Int = 50

    public init() {}

    public var engineStartupFraction: Double {
        Double(engineStartupPercentBucket) / 100.0
    }

    public func updateEngineStartupFraction(_ rawFraction: Double?) {
        let clamped = min(1.0, max(0.0, rawFraction ?? 0.5))
        let bucket = Int((clamped * 100.0).rounded())
        if bucket != engineStartupPercentBucket {
            engineStartupPercentBucket = bucket
        }
    }
}
