import Foundation
import Observation

public struct PlaybackStopReceipt: Sendable, Equatable {
    public let itemId: String
    public let mediaType: String
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let completed: Bool
    public let recordedAt: Date

    public init(
        itemId: String,
        mediaType: String,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool,
        recordedAt: Date = Date()
    ) {
        self.itemId = itemId
        self.mediaType = mediaType
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.completed = completed
        self.recordedAt = recordedAt
    }
}

@MainActor
@Observable
public final class PlaybackStopReceiptStore {
    public private(set) var lastReceipt: PlaybackStopReceipt?

    @ObservationIgnored
    private var waiters: [UUID: (itemId: String, continuation: CheckedContinuation<PlaybackStopReceipt?, Never>)] = [:]

    public init() {}

    public func record(_ receipt: PlaybackStopReceipt) {
        lastReceipt = receipt
        let matchingIDs = waiters.compactMap { id, entry in
            entry.itemId == receipt.itemId ? id : nil
        }
        for id in matchingIDs {
            if let entry = waiters.removeValue(forKey: id) {
                entry.continuation.resume(returning: receipt)
            }
        }
    }

    public func awaitReceipt(
        for itemId: String,
        timeout: Duration = .seconds(3),
        recentGraceSeconds: TimeInterval = 5.0,
        recordedAfter: Date? = nil,
        excluding preLaunchReceipt: PlaybackStopReceipt? = nil
    ) async -> PlaybackStopReceipt? {
        let isEligible: (PlaybackStopReceipt) -> Bool = { existing in
            guard existing.itemId == itemId,
                  abs(Date().timeIntervalSince(existing.recordedAt)) <= recentGraceSeconds else {
                return false
            }
            if let preLaunchReceipt, existing == preLaunchReceipt {
                return false
            }
            if let recordedAfter, existing.recordedAt < recordedAfter {
                return false
            }
            return true
        }
        if let existing = lastReceipt, isEligible(existing) {
            return existing
        }
        if Task.isCancelled || timeout <= .zero {
            return nil
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let existing = lastReceipt, isEligible(existing) {
                    continuation.resume(returning: existing)
                    return
                }
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                waiters[waiterID] = (itemId: itemId, continuation: continuation)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: timeout)
                    if let entry = self?.waiters.removeValue(forKey: waiterID) {
                        entry.continuation.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let entry = self?.waiters.removeValue(forKey: waiterID) {
                    entry.continuation.resume(returning: nil)
                }
            }
        }
    }
}
