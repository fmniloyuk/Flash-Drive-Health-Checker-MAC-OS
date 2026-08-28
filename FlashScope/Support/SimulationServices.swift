import Foundation
import FlashScopeCore

struct SimulationProfile: Sendable {
    let name: String
    let input: DiagnosisInput
}

enum SimulationCatalog {
    static let profiles: [SimulationProfile] = DiagnosticFixtures.profiles().enumerated().map { index, pair in
        let (name, source) = pair
        let id = "sim-disk-\(index)"
        let drive = PhysicalDrive(
            id: id,
            bsdName: "disk\(90 + index)",
            displayName: name,
            manufacturer: source.drive.manufacturer,
            model: source.drive.model,
            serialNumber: .available("SIM-\(index)-REDACT-ME"),
            capacityBytes: source.drive.capacityBytes,
            isRemovable: source.drive.isRemovable,
            isEjectable: source.drive.isEjectable,
            isInternal: false,
            isExternal: true,
            capabilities: source.drive.capabilities
        )
        let volume = Volume(
            id: "\(id)-volume",
            physicalDriveID: id,
            bsdName: "disk\(90 + index)s1",
            name: source.volume.name,
            mountPath: "/Volumes/FlashScope Simulation \(index + 1)",
            capacityBytes: source.volume.capacityBytes,
            availableBytes: source.volume.availableBytes,
            filesystem: source.volume.filesystem,
            partitionScheme: source.volume.partitionScheme,
            isMounted: source.volume.isMounted,
            isReadOnly: source.volume.isReadOnly,
            isRemovable: true,
            isEjectable: true
        )
        var input = source
        input.drive = drive
        input.volume = volume
        return SimulationProfile(name: name, input: input)
    }

    static func profile(for driveID: String) -> SimulationProfile? { profiles.first { $0.input.drive.id == driveID } }
}

struct SimulationDriveDiscoveryService: DriveDiscoveryService {
    let empty: Bool
    init(empty: Bool = false) { self.empty = empty }
    func connectedDrives() async throws -> [PhysicalDrive] { empty ? [] : SimulationCatalog.profiles.map { $0.input.drive } }
    func events() -> AsyncStream<[PhysicalDrive]> {
        AsyncStream { continuation in
            continuation.yield(empty ? [] : SimulationCatalog.profiles.map { $0.input.drive })
            continuation.finish()
        }
    }
}

struct SimulationVolumeInformationService: VolumeInformationService {
    func volumes(for drive: PhysicalDrive) async throws -> [Volume] { SimulationCatalog.profile(for: drive.id).map { [$0.input.volume] } ?? [] }
}

struct SimulationUSBTopologyService: USBTopologyService {
    func connection(for drive: PhysicalDrive) async -> USBConnection { SimulationCatalog.profile(for: drive.id)?.input.connection ?? .init() }
}

struct SimulationHealthSignalService: HealthSignalService {
    func signals(for drive: PhysicalDrive) async -> [HealthSignal] { SimulationCatalog.profile(for: drive.id)?.input.healthSignals ?? [] }
}

struct SimulationFilesystemVerificationService: FilesystemVerificationService {
    func verify(volume: Volume, allowNormalUnmount: Bool) async -> FilesystemCheckResult {
        guard allowNormalUnmount else { return .init(status: .unableToRun, summary: "Simulation: explicit unmount confirmation was not provided", requiredUnmount: true) }
        try? await Task.sleep(for: .milliseconds(350))
        return SimulationCatalog.profiles.first(where: { $0.input.volume.id == volume.id })?.input.filesystemCheck
            ?? .init(status: .passed, summary: "Simulation: verification completed")
    }
}

actor SimulationBenchmarkService: BenchmarkService {
    func run(target: BenchmarkTarget, configuration: BenchmarkConfiguration, progress: @escaping @Sendable (BenchmarkProgress) -> Void) async throws -> BenchmarkResult {
        guard let profile = SimulationCatalog.profile(for: target.drive.id) else { throw BenchmarkError.nonRemovableTargetRejected }
        if target.volume.isReadOnly { throw BenchmarkError.readOnlyVolume }
        let phases: [BenchmarkPhase] = [.preparing, .writing, .flushing, .reading, .verifying, .cleaningUp]
        for (index, phase) in phases.enumerated() {
            try Task.checkCancellation()
            progress(.init(phase: phase, completedBytes: UInt64(index) * configuration.sizeBytes / UInt64(phases.count), totalBytes: configuration.sizeBytes, currentMegabytesPerSecond: phase == .writing ? profile.input.benchmark?.writeMegabytesPerSecond : phase == .reading ? profile.input.benchmark?.readMegabytesPerSecond : nil, message: "Simulation: \(phase.rawValue)"))
            try await Task.sleep(for: .milliseconds(120))
        }
        if profile.name == "Drive removed" { throw BenchmarkError.readFailed("Simulation: the drive was removed during the benchmark") }
        guard var result = profile.input.benchmark else { throw BenchmarkError.readOnlyVolume }
        result.configuration = configuration
        progress(.init(phase: .completed, completedBytes: configuration.sizeBytes, totalBytes: configuration.sizeBytes, message: "Simulation complete"))
        return result
    }
}
