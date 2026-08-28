import Foundation

public protocol DriveDiscoveryService: Sendable {
    func connectedDrives() async throws -> [PhysicalDrive]
    func events() -> AsyncStream<[PhysicalDrive]>
}

public protocol USBTopologyService: Sendable {
    func connection(for drive: PhysicalDrive) async -> USBConnection
}

public protocol VolumeInformationService: Sendable {
    func volumes(for drive: PhysicalDrive) async throws -> [Volume]
}

public protocol BenchmarkService: Sendable {
    func run(
        target: BenchmarkTarget,
        configuration: BenchmarkConfiguration,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult
}

public protocol FilesystemVerificationService: Sendable {
    func verify(volume: Volume, allowNormalUnmount: Bool) async -> FilesystemCheckResult
}

public protocol HealthSignalService: Sendable {
    func signals(for drive: PhysicalDrive) async -> [HealthSignal]
}

public protocol DiagnosisEngine: Sendable {
    func diagnose(_ input: DiagnosisInput) -> DiagnosisReport
}

public protocol ReportGenerator: Sendable {
    func jsonReport(for session: TestSession, options: ReportRedactionOptions) throws -> Data
    func plainTextReport(for session: TestSession, options: ReportRedactionOptions) -> String
}

@MainActor
public protocol HistoryRepository: Sendable {
    func save(_ session: TestSession) async throws
    func sessions(for driveIdentityHash: String) async throws -> [TestSession]
    func delete(_ sessionID: UUID) async throws
    func deleteAll() async throws
}

public struct BenchmarkTarget: Codable, Equatable, Sendable {
    public var drive: PhysicalDrive
    public var volume: Volume

    public init(drive: PhysicalDrive, volume: Volume) {
        self.drive = drive
        self.volume = volume
    }
}

public struct DiagnosisInput: Codable, Equatable, Sendable {
    public var drive: PhysicalDrive
    public var volume: Volume
    public var connection: USBConnection
    public var benchmark: BenchmarkResult?
    public var filesystemCheck: FilesystemCheckResult
    public var healthSignals: [HealthSignal]
    public var historicalBenchmarks: [BenchmarkResult]

    public init(drive: PhysicalDrive, volume: Volume, connection: USBConnection, benchmark: BenchmarkResult?, filesystemCheck: FilesystemCheckResult = .init(status: .notRun, summary: "Not run"), healthSignals: [HealthSignal] = [], historicalBenchmarks: [BenchmarkResult] = []) {
        self.drive = drive
        self.volume = volume
        self.connection = connection
        self.benchmark = benchmark
        self.filesystemCheck = filesystemCheck
        self.healthSignals = healthSignals
        self.historicalBenchmarks = historicalBenchmarks
    }
}

public struct ReportRedactionOptions: Codable, Equatable, Sendable {
    public var redactSerialNumber: Bool
    public var redactUsernamesInPaths: Bool

    public init(redactSerialNumber: Bool = true, redactUsernamesInPaths: Bool = true) {
        self.redactSerialNumber = redactSerialNumber
        self.redactUsernamesInPaths = redactUsernamesInPaths
    }
}
