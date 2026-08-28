import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct BenchmarkOwnershipMarker: Codable, Equatable, Sendable {
    public static let owner = "com.example.FlashScope"
    public static let schemaVersion = 1
    public var owner: String
    public var schemaVersion: Int
    public var token: String
    public var createdAt: Date

    public init(token: String, createdAt: Date = Date()) {
        self.owner = Self.owner
        self.schemaVersion = Self.schemaVersion
        self.token = token
        self.createdAt = createdAt
    }
}

public struct CleanupRecoveryNotice: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var path: String
    public var cleaned: Bool
    public var message: String

    public init(id: UUID = UUID(), path: String, cleaned: Bool, message: String) {
        self.id = id
        self.path = path
        self.cleaned = cleaned
        self.message = message
    }
}

public actor OrphanedBenchmarkCleanupService {
    public static let markerFilename = "ownership.json"

    public init() {}

    public func scanAndClean(mountRoot: URL) -> [CleanupRecoveryNotice] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: mountRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            // skipsHiddenFiles hides FlashScope directories, so intentionally fall back to an unfiltered listing.
            return scanUnfiltered(mountRoot: mountRoot)
        }
        // This normally contains no hidden benchmark paths; scan unfiltered is authoritative.
        _ = entries
        return scanUnfiltered(mountRoot: mountRoot)
    }

    private func scanUnfiltered(mountRoot: URL) -> [CleanupRecoveryNotice] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: mountRoot, includingPropertiesForKeys: nil) else { return [] }
        var notices: [CleanupRecoveryNotice] = []
        for directory in entries where directory.lastPathComponent.hasPrefix(SafeTemporaryPath.directoryPrefix) {
            do {
                try SafeTemporaryPath.validateOwnedDirectory(directory, mountRoot: mountRoot)
                let token = String(directory.lastPathComponent.dropFirst(SafeTemporaryPath.directoryPrefix.count))
                guard UUID(uuidString: token) != nil else { throw SafePathError.invalidOwnedDirectoryName }
                let markerURL = directory.appendingPathComponent(Self.markerFilename)
                let markerIdentity = try SafeTemporaryPath.identity(of: markerURL)
                let markerData = try Data(contentsOf: markerURL, options: [.mappedIfSafe])
                let marker = try JSONDecoder().decode(BenchmarkOwnershipMarker.self, from: markerData)
                guard marker.owner == BenchmarkOwnershipMarker.owner, marker.schemaVersion == BenchmarkOwnershipMarker.schemaVersion, marker.token == token else {
                    notices.append(.init(path: directory.path, cleaned: false, message: "Ownership marker did not match; FlashScope left the directory untouched."))
                    continue
                }
                let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                let allowed = Set([SafeTemporaryPath.benchmarkFilename, Self.markerFilename])
                guard children.allSatisfy({ allowed.contains($0.lastPathComponent) }) else {
                    notices.append(.init(path: directory.path, cleaned: false, message: "Unexpected files were present; automatic cleanup was intentionally refused."))
                    continue
                }
                if let payload = children.first(where: { $0.lastPathComponent == SafeTemporaryPath.benchmarkFilename }) {
                    let payloadIdentity = try SafeTemporaryPath.identity(of: payload)
                    try SafeTemporaryPath.validateFile(payload, expectedIdentity: payloadIdentity)
                    guard unlink(payload.path) == 0 else { throw POSIXError(.EIO) }
                }
                try SafeTemporaryPath.validateFile(markerURL, expectedIdentity: markerIdentity)
                guard unlink(markerURL.path) == 0 else { throw POSIXError(.EIO) }
                guard rmdir(directory.path) == 0 else { throw POSIXError(.EIO) }
                notices.append(.init(path: directory.path, cleaned: true, message: "Recovered and removed a verified orphaned FlashScope benchmark workspace."))
            } catch {
                notices.append(.init(path: directory.path, cleaned: false, message: "Automatic cleanup was refused: \(error.localizedDescription)"))
            }
        }
        return notices
    }
}
