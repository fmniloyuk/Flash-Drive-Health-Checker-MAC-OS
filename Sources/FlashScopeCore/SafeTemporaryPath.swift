import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SafePathError: Error, Equatable, LocalizedError, Sendable {
    case invalidMountRoot
    case targetOutsideMount
    case invalidOwnedDirectoryName
    case symbolicLinkRejected
    case wrongFileIdentity
    case wrongFileType

    public var errorDescription: String? {
        switch self {
        case .invalidMountRoot: "The volume mount root is invalid."
        case .targetOutsideMount: "The cleanup target is outside the selected volume."
        case .invalidOwnedDirectoryName: "The path is not an application-owned benchmark directory."
        case .symbolicLinkRejected: "Symbolic links are never followed during benchmark cleanup."
        case .wrongFileIdentity: "The benchmark file identity changed, so cleanup was stopped."
        case .wrongFileType: "The benchmark target is not the expected regular file or directory."
        }
    }
}

public struct FileIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public enum SafeTemporaryPath {
    public static let directoryPrefix = ".FlashScope-Benchmark-"
    public static let benchmarkFilename = "payload.bin"

    public static func validateOwnedDirectory(_ directory: URL, mountRoot: URL) throws {
        let root = mountRoot.standardizedFileURL.path
        let target = directory.standardizedFileURL.path
        guard !root.isEmpty, root.hasPrefix("/") else { throw SafePathError.invalidMountRoot }
        let expectedPrefix = root.hasSuffix("/") ? root : root + "/"
        guard target.hasPrefix(expectedPrefix) else { throw SafePathError.targetOutsideMount }
        guard directory.lastPathComponent.hasPrefix(directoryPrefix), directory.lastPathComponent.count > directoryPrefix.count else {
            throw SafePathError.invalidOwnedDirectoryName
        }
        if fileExists(directory) { try rejectSymlink(directory, expectedDirectory: true) }
    }

    public static func identity(of url: URL) throws -> FileIdentity {
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        guard result == 0 else { throw POSIXError(.ENOENT) }
        if (info.st_mode & S_IFMT) == S_IFLNK { throw SafePathError.symbolicLinkRejected }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    public static func validateFile(_ url: URL, expectedIdentity: FileIdentity) throws {
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        guard result == 0 else { throw POSIXError(.ENOENT) }
        if (info.st_mode & S_IFMT) == S_IFLNK { throw SafePathError.symbolicLinkRejected }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw SafePathError.wrongFileType }
        let identity = FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
        guard identity == expectedIdentity else { throw SafePathError.wrongFileIdentity }
    }

    private static func rejectSymlink(_ url: URL, expectedDirectory: Bool) throws {
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        guard result == 0 else { return }
        if (info.st_mode & S_IFMT) == S_IFLNK { throw SafePathError.symbolicLinkRejected }
        let expected = expectedDirectory ? S_IFDIR : S_IFREG
        guard (info.st_mode & S_IFMT) == expected else { throw SafePathError.wrongFileType }
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
