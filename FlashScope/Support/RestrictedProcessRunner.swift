import Foundation
import OSLog

struct RestrictedCommandResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum DiskUtilityOperation: Sendable, Equatable {
    case listExternalPhysical
    case info(String)
    case verifyVolume(String)

    var arguments: [String] {
        switch self {
        case .listExternalPhysical:
            ["list", "-plist", "external", "physical"]
        case let .info(bsdName):
            ["info", "-plist", "/dev/\(bsdName)"]
        case let .verifyVolume(bsdName):
            ["verifyVolume", "/dev/\(bsdName)"]
        }
    }
}

enum RestrictedProcessError: Error, LocalizedError {
    case invalidBSDName
    case executableUnavailable
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBSDName: "The disk identifier was rejected by the safety validator."
        case .executableUnavailable: "The macOS disk utility is unavailable."
        case let .launchFailed(message): "The restricted system command could not run: \(message)"
        }
    }
}

protocol DiskUtilityRunning: Sendable {
    func run(_ operation: DiskUtilityOperation) async throws -> RestrictedCommandResult
}

actor RestrictedProcessRunner: DiskUtilityRunning {
    private let logger = Logger(subsystem: "com.example.FlashScope", category: "system-command")
    private let diskutilURL = URL(fileURLWithPath: "/usr/sbin/diskutil")

    func run(_ operation: DiskUtilityOperation) async throws -> RestrictedCommandResult {
        switch operation {
        case .listExternalPhysical: break
        case let .info(name), let .verifyVolume(name):
            guard Self.isValidBSDName(name) else { throw RestrictedProcessError.invalidBSDName }
        }
        guard FileManager.default.isExecutableFile(atPath: diskutilURL.path) else {
            throw RestrictedProcessError.executableUnavailable
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = diskutilURL
        process.arguments = operation.arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = nil
        do { try process.run() }
        catch {
            logger.error("Restricted disk utility launch failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw RestrictedProcessError.launchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        return .init(status: process.terminationStatus, stdout: output, stderr: errorOutput)
    }

    static func isValidBSDName(_ value: String) -> Bool {
        let pattern = #"^disk[0-9]+(?:s[0-9]+)?$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
