import AetherBridge
import CoreText
import Foundation
import Observation

/// Manages per-session MKV/ASS embedded fonts via off-main-actor `CTFontManager` parsing,
/// SHA-256 deduplication, `.cachesDirectory` storage, and `.process`-scope registration/unregistration.
@MainActor
@Observable
final class EmbeddedFontRegistry {
    private(set) var registrationRevision: UInt64 = 0

    @ObservationIgnored private var activeFingerprints: [String] = []
    @ObservationIgnored private var registeredFilesByHash: [String: URL] = [:]
    @ObservationIgnored private var ownedRegisteredHashes: Set<String> = []
    @ObservationIgnored private var descriptorByNormalizedKey: [String: CTFontDescriptor] = [:]
    @ObservationIgnored private var ingestionGeneration: UInt64 = 0
    @ObservationIgnored private var ingestTask: Task<Void, Never>?
    @ObservationIgnored private let sessionNonce: String
    @ObservationIgnored private let cacheDirectoryURL: URL?

    struct RawFontAttachment: Sendable {
        let filename: String
        let mimeType: String
        let data: Data
    }

    private struct ParsedFontAttachmentPayload: @unchecked Sendable {
        let sha256: String
        let fileURL: URL
        let entries: [(key: String, descriptor: CTFontDescriptor)]
    }

    private struct OffMainIngestionResult: Sendable {
        let orderedFingerprints: [String]
        let payloads: [ParsedFontAttachmentPayload]
    }

    init(
        sessionNonce: String = UUID().uuidString.lowercased(),
        cacheDirectoryURL: URL? = nil
    ) {
        self.sessionNonce = sessionNonce
        if let cacheDirectoryURL {
            self.cacheDirectoryURL = cacheDirectoryURL
        } else {
            self.cacheDirectoryURL = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Luna/EmbeddedFonts/\(sessionNonce)", isDirectory: true)
        }
    }

    var registeredFontCount: Int {
        registeredFilesByHash.count
    }

    var activeIngestTask: Task<Void, Never>? {
        ingestTask
    }

    func descriptor(forFontName rawFontName: String) -> CTFontDescriptor? {
        for key in EmbeddedFontNamePolicy.normalizedLookupKeys(for: rawFontName) {
            if let match = descriptorByNormalizedKey[key] {
                return match
            }
        }
        return nil
    }

    func ingest(attachments: [FontAttachment]) {
        ingestRawAttachments(
            attachments.map {
                RawFontAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
            }
        )
    }

    func ingestRawAttachments(_ attachments: [RawFontAttachment]) {
        if attachments.isEmpty {
            clearAndUnregisterAll()
            return
        }

        ingestionGeneration &+= 1
        let expectedGeneration = ingestionGeneration
        ingestTask?.cancel()
        let previousFingerprints = activeFingerprints
        let existingFileURLs = registeredFilesByHash
        let targetDirectory = cacheDirectoryURL

        ingestTask = Task.detached(priority: .utility) {
            let result = Self.parseAttachmentsOffMain(
                attachments,
                previousFingerprints: previousFingerprints,
                existingFileURLs: existingFileURLs,
                cacheDirectoryURL: targetDirectory
            )
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.ingestionGeneration == expectedGeneration else {
                    return
                }
                self.ingestTask = nil
                guard let result else { return }
                self.applyParsedIngestionResult(result)
            }
        }
    }

    func clearAndUnregisterAll() {
        ingestionGeneration &+= 1
        ingestTask?.cancel()
        ingestTask = nil

        let hadState = !registeredFilesByHash.isEmpty
            || !descriptorByNormalizedKey.isEmpty
            || !activeFingerprints.isEmpty

        for (hash, fileURL) in registeredFilesByHash {
            if ownedRegisteredHashes.contains(hash) {
                _ = CTFontManagerUnregisterFontsForURL(fileURL as CFURL, .process, nil)
            }
        }
        ownedRegisteredHashes.removeAll()
        registeredFilesByHash.removeAll()
        descriptorByNormalizedKey.removeAll()
        activeFingerprints.removeAll()

        if let cacheDirectoryURL {
            try? FileManager.default.removeItem(at: cacheDirectoryURL)
        }
        if hadState {
            registrationRevision &+= 1
        }
    }

    private func applyParsedIngestionResult(_ result: OffMainIngestionResult) {
        let nextHashes = Set(result.orderedFingerprints)
        let staleHashes = registeredFilesByHash.keys.filter { !nextHashes.contains($0) }
        for staleHash in staleHashes {
            if let oldURL = registeredFilesByHash.removeValue(forKey: staleHash) {
                if ownedRegisteredHashes.remove(staleHash) != nil {
                    _ = CTFontManagerUnregisterFontsForURL(oldURL as CFURL, .process, nil)
                }
                try? FileManager.default.removeItem(at: oldURL)
            }
        }

        var nextDescriptors: [String: CTFontDescriptor] = [:]
        var activeHashes: [String] = []

        for payload in result.payloads {
            var isRegistered = registeredFilesByHash[payload.sha256] != nil
            if !isRegistered {
                var registerError: Unmanaged<CFError>?
                let registered = CTFontManagerRegisterFontsForURL(
                    payload.fileURL as CFURL,
                    .process,
                    &registerError
                )
                if registered {
                    ownedRegisteredHashes.insert(payload.sha256)
                    registeredFilesByHash[payload.sha256] = payload.fileURL
                    isRegistered = true
                } else if let cfErr = registerError?.takeRetainedValue(),
                          CFErrorGetCode(cfErr) == CTFontManagerError.alreadyRegistered.rawValue {
                    registeredFilesByHash[payload.sha256] = payload.fileURL
                    isRegistered = true
                } else {
                    try? FileManager.default.removeItem(at: payload.fileURL)
                }
            }

            if isRegistered {
                activeHashes.append(payload.sha256)
                for entry in payload.entries where nextDescriptors[entry.key] == nil {
                    nextDescriptors[entry.key] = entry.descriptor
                }
            }
        }

        if result.payloads.isEmpty && staleHashes.isEmpty && registeredFilesByHash.isEmpty {
            return
        }

        activeFingerprints = activeHashes
        descriptorByNormalizedKey = nextDescriptors
        registrationRevision &+= 1
    }

    private nonisolated static func parseAttachmentsOffMain(
        _ attachments: [RawFontAttachment],
        previousFingerprints: [String],
        existingFileURLs: [String: URL],
        cacheDirectoryURL: URL?
    ) -> OffMainIngestionResult? {
        guard let cacheDirectoryURL else { return nil }

        var seenHashes = Set<String>()
        var deduplicated: [(sha256: String, ext: String, data: Data)] = []
        var orderedFingerprints: [String] = []

        for attachment in attachments {
            guard !Task.isCancelled else { return nil }
            guard !attachment.data.isEmpty,
                  EmbeddedFontNamePolicy.isSupportedFontAttachment(
                      filename: attachment.filename,
                      mimeType: attachment.mimeType
                  ) else {
                continue
            }
            let sha256 = EmbeddedFontNamePolicy.sha256Hex(for: attachment.data)
            guard seenHashes.insert(sha256).inserted else { continue }
            let ext = EmbeddedFontNamePolicy.preferredFontExtension(
                filename: attachment.filename,
                mimeType: attachment.mimeType
            )
            orderedFingerprints.append(sha256)
            deduplicated.append((sha256: sha256, ext: ext, data: attachment.data))
        }

        if orderedFingerprints == previousFingerprints && !orderedFingerprints.isEmpty {
            return nil
        }
        if deduplicated.isEmpty {
            return OffMainIngestionResult(orderedFingerprints: [], payloads: [])
        }

        let fm = FileManager.default
        guard !Task.isCancelled else { return nil }
        do {
            try fm.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var payloads: [ParsedFontAttachmentPayload] = []
        payloads.reserveCapacity(deduplicated.count)
        var newlyWrittenURLs: [URL] = []

        func cleanupNewlyWrittenOnCancellation() {
            for url in newlyWrittenURLs {
                try? fm.removeItem(at: url)
            }
            if let contents = try? fm.contentsOfDirectory(atPath: cacheDirectoryURL.path), contents.isEmpty {
                try? fm.removeItem(at: cacheDirectoryURL)
            }
        }

        for item in deduplicated {
            guard !Task.isCancelled else {
                cleanupNewlyWrittenOnCancellation()
                return nil
            }
            guard let cfDescriptors = CTFontManagerCreateFontDescriptorsFromData(item.data as CFData) as? [CTFontDescriptor],
                  !cfDescriptors.isEmpty else {
                continue
            }

            var entries: [(key: String, descriptor: CTFontDescriptor)] = []
            for descriptor in cfDescriptors {
                let candidateNames: [String?] = [
                    CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                    CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String,
                    CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                ]
                for rawName in candidateNames.compactMap({ $0 }) {
                    for key in EmbeddedFontNamePolicy.normalizedLookupKeys(for: rawName) {
                        entries.append((key: key, descriptor: descriptor))
                    }
                }
            }
            guard !entries.isEmpty else { continue }

            let fileURL = existingFileURLs[item.sha256]
                ?? cacheDirectoryURL.appendingPathComponent("\(item.sha256).\(item.ext)", isDirectory: false)
            if !fm.fileExists(atPath: fileURL.path) {
                guard !Task.isCancelled else {
                    cleanupNewlyWrittenOnCancellation()
                    return nil
                }
                do {
                    try item.data.write(to: fileURL, options: .atomic)
                    newlyWrittenURLs.append(fileURL)
                    if Task.isCancelled {
                        cleanupNewlyWrittenOnCancellation()
                        return nil
                    }
                } catch {
                    continue
                }
            }

            payloads.append(ParsedFontAttachmentPayload(
                sha256: item.sha256,
                fileURL: fileURL,
                entries: entries
            ))
        }

        guard !Task.isCancelled else {
            cleanupNewlyWrittenOnCancellation()
            return nil
        }
        return OffMainIngestionResult(
            orderedFingerprints: payloads.map(\.sha256),
            payloads: payloads
        )
    }
}
