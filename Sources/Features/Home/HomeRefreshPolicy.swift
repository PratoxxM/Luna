import Foundation

public enum HomeRefreshPolicy: Sendable {
    public nonisolated static func shouldRevalidateOnForeground(
        isSceneActive: Bool,
        isActiveTab: Bool,
        hasActivePlayback: Bool,
        secondsSinceLastValidation: TimeInterval,
        minimumIntervalSeconds: TimeInterval = 10
    ) -> Bool {
        guard isSceneActive, isActiveTab, !hasActivePlayback else {
            return false
        }
        return secondsSinceLastValidation >= minimumIntervalSeconds
    }
}
