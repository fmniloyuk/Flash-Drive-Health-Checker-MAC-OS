import Foundation

public enum FilesystemType: String, Codable, CaseIterable, Sendable {
    case fat32 = "FAT32"
    case exfat = "exFAT"
    case apfs = "APFS"
    case hfsPlus = "HFS+"
    case ntfs = "NTFS"
    case other = "Other"
    case unknown = "Unknown"
}

public enum PartitionScheme: String, Codable, Sendable {
    case guid = "GUID Partition Map"
    case masterBootRecord = "Master Boot Record"
    case applePartitionMap = "Apple Partition Map"
    case unknown = "Unknown"
}

public enum USBSpecification: String, Codable, CaseIterable, Sendable {
    case usb1 = "USB 1.x"
    case usb2 = "USB 2.0"
    case usb3 = "USB 3.x"
    case usb4 = "USB4"
}

public struct USBLinkSpeed: Codable, Equatable, Sendable {
    public let megabitsPerSecond: Double
    public let label: String

    public init(megabitsPerSecond: Double, label: String? = nil) {
        self.megabitsPerSecond = megabitsPerSecond
        self.label = label ?? USBLinkSpeed.defaultLabel(for: megabitsPerSecond)
    }

    public var theoreticalMegabytesPerSecond: Double { megabitsPerSecond / 8.0 }

    public var classLabel: String {
        switch megabitsPerSecond {
        case ..<2: "Low Speed"
        case ..<13: "Full Speed"
        case ..<1_000: "High Speed"
        case ..<7_500: "SuperSpeed 5 Gb/s"
        case ..<15_000: "SuperSpeed 10 Gb/s"
        case ..<30_000: "20 Gb/s"
        default: "40 Gb/s+"
        }
    }

    private static func defaultLabel(for mbps: Double) -> String {
        if mbps >= 1_000 { return String(format: "%.0f Gb/s", mbps / 1_000.0) }
        return String(format: "%.0f Mb/s", mbps)
    }
}

public struct DriveCapabilities: Codable, Equatable, Sendable {
    public var declaredUSBSpecification: EvidenceAvailability<USBSpecification>
    public var supportsSMART: EvidenceAvailability<Bool>

    public init(
        declaredUSBSpecification: EvidenceAvailability<USBSpecification> = .unavailable("Not reported by the device"),
        supportsSMART: EvidenceAvailability<Bool> = .unsupported("Not supported or not exposed")
    ) {
        self.declaredUSBSpecification = declaredUSBSpecification
        self.supportsSMART = supportsSMART
    }
}

public struct PhysicalDrive: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var bsdName: String
    public var displayName: String
    public var manufacturer: EvidenceAvailability<String>
    public var model: EvidenceAvailability<String>
    public var serialNumber: EvidenceAvailability<String>
    public var capacityBytes: UInt64
    public var isRemovable: Bool
    public var isEjectable: Bool
    public var isInternal: Bool
    public var isExternal: Bool
    public var capabilities: DriveCapabilities

    public init(
        id: String,
        bsdName: String,
        displayName: String,
        manufacturer: EvidenceAvailability<String> = .unavailable("Unavailable"),
        model: EvidenceAvailability<String> = .unavailable("Unavailable"),
        serialNumber: EvidenceAvailability<String> = .unavailable("Unavailable"),
        capacityBytes: UInt64,
        isRemovable: Bool,
        isEjectable: Bool,
        isInternal: Bool,
        isExternal: Bool,
        capabilities: DriveCapabilities = .init()
    ) {
        self.id = id
        self.bsdName = bsdName
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.capacityBytes = capacityBytes
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isInternal = isInternal
        self.isExternal = isExternal
        self.capabilities = capabilities
    }
}

public struct Volume: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let physicalDriveID: String
    public var bsdName: String
    public var name: String
    public var mountPath: String
    public var capacityBytes: UInt64
    public var availableBytes: UInt64
    public var filesystem: EvidenceAvailability<FilesystemType>
    public var partitionScheme: EvidenceAvailability<PartitionScheme>
    public var isMounted: Bool
    public var isReadOnly: Bool
    public var isRemovable: Bool
    public var isEjectable: Bool

    public init(
        id: String,
        physicalDriveID: String,
        bsdName: String,
        name: String,
        mountPath: String,
        capacityBytes: UInt64,
        availableBytes: UInt64,
        filesystem: EvidenceAvailability<FilesystemType>,
        partitionScheme: EvidenceAvailability<PartitionScheme> = .unavailable("Unavailable"),
        isMounted: Bool,
        isReadOnly: Bool,
        isRemovable: Bool,
        isEjectable: Bool
    ) {
        self.id = id
        self.physicalDriveID = physicalDriveID
        self.bsdName = bsdName
        self.name = name
        self.mountPath = mountPath
        self.capacityBytes = capacityBytes
        self.availableBytes = availableBytes
        self.filesystem = filesystem
        self.partitionScheme = partitionScheme
        self.isMounted = isMounted
        self.isReadOnly = isReadOnly
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
    }

    public var usedBytes: UInt64 { capacityBytes > availableBytes ? capacityBytes - availableBytes : 0 }
    public var freeFraction: Double { capacityBytes == 0 ? 0 : Double(availableBytes) / Double(capacityBytes) }
}

public struct USBTopologyNode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String

    public init(id: String, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct USBConnection: Codable, Equatable, Sendable {
    public var declaredSpecification: EvidenceAvailability<USBSpecification>
    public var negotiatedSpeed: EvidenceAvailability<USBLinkSpeed>
    public var vendorID: EvidenceAvailability<UInt16>
    public var productID: EvidenceAvailability<UInt16>
    public var portPath: EvidenceAvailability<String>
    public var topology: [USBTopologyNode]
    public var hubOrAdapterDetected: EvidenceAvailability<Bool>
    public var allocatedMilliAmps: EvidenceAvailability<Int>
    public var availableMilliAmps: EvidenceAvailability<Int>

    public init(
        declaredSpecification: EvidenceAvailability<USBSpecification> = .unavailable("Unavailable"),
        negotiatedSpeed: EvidenceAvailability<USBLinkSpeed> = .unavailable("Unavailable"),
        vendorID: EvidenceAvailability<UInt16> = .unavailable("Unavailable"),
        productID: EvidenceAvailability<UInt16> = .unavailable("Unavailable"),
        portPath: EvidenceAvailability<String> = .unavailable("Unavailable"),
        topology: [USBTopologyNode] = [],
        hubOrAdapterDetected: EvidenceAvailability<Bool> = .unavailable("Unavailable"),
        allocatedMilliAmps: EvidenceAvailability<Int> = .unavailable("Unavailable"),
        availableMilliAmps: EvidenceAvailability<Int> = .unavailable("Unavailable")
    ) {
        self.declaredSpecification = declaredSpecification
        self.negotiatedSpeed = negotiatedSpeed
        self.vendorID = vendorID
        self.productID = productID
        self.portPath = portPath
        self.topology = topology
        self.hubOrAdapterDetected = hubOrAdapterDetected
        self.allocatedMilliAmps = allocatedMilliAmps
        self.availableMilliAmps = availableMilliAmps
    }
}

public enum BenchmarkPreset: String, Codable, CaseIterable, Sendable {
    case quick
    case standard
    case extended
    case custom

    public var defaultBytes: UInt64 {
        switch self {
        case .quick: 256 * 1_024 * 1_024
        case .standard: 1_024 * 1_024 * 1_024
        case .extended: 4 * 1_024 * 1_024 * 1_024
        case .custom: 1_024 * 1_024 * 1_024
        }
    }
}

public enum BenchmarkDataPattern: String, Codable, Sendable {
    case deterministicPseudoRandom
    case cryptographicallyRandom
}

public struct BenchmarkConfiguration: Codable, Equatable, Sendable {
    public var preset: BenchmarkPreset
    public var sizeBytes: UInt64
    public var sampleIntervalSeconds: Double
    public var dataPattern: BenchmarkDataPattern
    public var includeSmallFileWorkload: Bool
    public var customSeed: UInt64

    public init(
        preset: BenchmarkPreset = .standard,
        sizeBytes: UInt64 = BenchmarkPreset.standard.defaultBytes,
        sampleIntervalSeconds: Double = 0.5,
        dataPattern: BenchmarkDataPattern = .deterministicPseudoRandom,
        includeSmallFileWorkload: Bool = false,
        customSeed: UInt64 = 0xF1A5_5C0E_2026
    ) {
        self.preset = preset
        self.sizeBytes = sizeBytes
        self.sampleIntervalSeconds = max(0.1, sampleIntervalSeconds)
        self.dataPattern = dataPattern
        self.includeSmallFileWorkload = includeSmallFileWorkload
        self.customSeed = customSeed
    }
}

public enum BenchmarkPhase: String, Codable, Sendable {
    case preparing
    case writing
    case flushing
    case reading
    case verifying
    case smallFiles
    case cleaningUp
    case completed
}

public struct BenchmarkProgress: Codable, Equatable, Sendable {
    public var phase: BenchmarkPhase
    public var completedBytes: UInt64
    public var totalBytes: UInt64
    public var currentMegabytesPerSecond: Double?
    public var message: String

    public init(phase: BenchmarkPhase, completedBytes: UInt64, totalBytes: UInt64, currentMegabytesPerSecond: Double? = nil, message: String) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentMegabytesPerSecond = currentMegabytesPerSecond
        self.message = message
    }

    public var fraction: Double { totalBytes == 0 ? 0 : min(1, Double(completedBytes) / Double(totalBytes)) }
}

public struct ThroughputSample: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var elapsedSeconds: Double
    public var megabytesPerSecond: Double
    public var phase: BenchmarkPhase

    public init(id: UUID = UUID(), elapsedSeconds: Double, megabytesPerSecond: Double, phase: BenchmarkPhase) {
        self.id = id
        self.elapsedSeconds = elapsedSeconds
        self.megabytesPerSecond = megabytesPerSecond
        self.phase = phase
    }
}

public struct BenchmarkStatistics: Codable, Equatable, Sendable {
    public var minimum: Double
    public var average: Double
    public var median: Double
    public var p95: Double
    public var maximum: Double
    public var coefficientOfVariation: Double

    public init(minimum: Double, average: Double, median: Double, p95: Double, maximum: Double, coefficientOfVariation: Double) {
        self.minimum = minimum
        self.average = average
        self.median = median
        self.p95 = p95
        self.maximum = maximum
        self.coefficientOfVariation = coefficientOfVariation
    }
}

public enum IntegrityStatus: String, Codable, Sendable {
    case passed
    case mismatch
    case notRun
}

public struct IntegrityResult: Codable, Equatable, Sendable {
    public var status: IntegrityStatus
    public var algorithm: String
    public var expectedDigest: String?
    public var actualDigest: String?

    public init(status: IntegrityStatus, algorithm: String = "SHA-256", expectedDigest: String? = nil, actualDigest: String? = nil) {
        self.status = status
        self.algorithm = algorithm
        self.expectedDigest = expectedDigest
        self.actualDigest = actualDigest
    }
}

public struct SmallFileResult: Codable, Equatable, Sendable {
    public var totalBytes: UInt64
    public var fileCount: Int
    public var megabytesPerSecond: Double
    public var filesPerSecond: Double
    public var operationsPerSecond: Double

    public init(totalBytes: UInt64, fileCount: Int, megabytesPerSecond: Double, filesPerSecond: Double, operationsPerSecond: Double) {
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.megabytesPerSecond = megabytesPerSecond
        self.filesPerSecond = filesPerSecond
        self.operationsPerSecond = operationsPerSecond
    }
}

public enum CleanupStatus: String, Codable, Sendable {
    case verified
    case alreadyGone
    case failed
}

public struct BenchmarkResult: Codable, Equatable, Sendable {
    public var configuration: BenchmarkConfiguration
    public var writeMegabytesPerSecond: Double
    public var readMegabytesPerSecond: Double
    public var writeDurationSeconds: Double
    public var readDurationSeconds: Double
    public var writeSamples: [ThroughputSample]
    public var readSamples: [ThroughputSample]
    public var writeStatistics: BenchmarkStatistics
    public var readStatistics: BenchmarkStatistics
    public var integrity: IntegrityResult
    public var smallFileResult: SmallFileResult?
    public var durableFlushIncluded: Bool
    public var readMayBeCached: Bool
    public var cleanupStatus: CleanupStatus
    public var ioErrorCount: Int

    public init(
        configuration: BenchmarkConfiguration,
        writeMegabytesPerSecond: Double,
        readMegabytesPerSecond: Double,
        writeDurationSeconds: Double,
        readDurationSeconds: Double,
        writeSamples: [ThroughputSample],
        readSamples: [ThroughputSample],
        writeStatistics: BenchmarkStatistics,
        readStatistics: BenchmarkStatistics,
        integrity: IntegrityResult,
        smallFileResult: SmallFileResult? = nil,
        durableFlushIncluded: Bool = true,
        readMayBeCached: Bool = true,
        cleanupStatus: CleanupStatus = .verified,
        ioErrorCount: Int = 0
    ) {
        self.configuration = configuration
        self.writeMegabytesPerSecond = writeMegabytesPerSecond
        self.readMegabytesPerSecond = readMegabytesPerSecond
        self.writeDurationSeconds = writeDurationSeconds
        self.readDurationSeconds = readDurationSeconds
        self.writeSamples = writeSamples
        self.readSamples = readSamples
        self.writeStatistics = writeStatistics
        self.readStatistics = readStatistics
        self.integrity = integrity
        self.smallFileResult = smallFileResult
        self.durableFlushIncluded = durableFlushIncluded
        self.readMayBeCached = readMayBeCached
        self.cleanupStatus = cleanupStatus
        self.ioErrorCount = ioErrorCount
    }
}

public enum FilesystemCheckStatus: String, Codable, Sendable {
    case passed
    case issuesDetected
    case unableToRun
    case permissionDenied
    case toolUnavailable
    case cancelled
    case notRun
}

public struct FilesystemCheckResult: Codable, Equatable, Sendable {
    public var status: FilesystemCheckStatus
    public var summary: String
    public var exitStatus: Int32?
    public var verificationTool: String?
    public var requiredUnmount: Bool
    public var remountedSuccessfully: Bool?

    public init(status: FilesystemCheckStatus, summary: String, exitStatus: Int32? = nil, verificationTool: String? = nil, requiredUnmount: Bool = false, remountedSuccessfully: Bool? = nil) {
        self.status = status
        self.summary = summary
        self.exitStatus = exitStatus
        self.verificationTool = verificationTool
        self.requiredUnmount = requiredUnmount
        self.remountedSuccessfully = remountedSuccessfully
    }
}

public enum HealthSignalKind: String, Codable, Sendable {
    case smart
    case ioErrors
    case power
    case temperature
    case writeProtection
}

public struct HealthSignal: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var kind: HealthSignalKind
    public var availability: EvidenceAvailability<String>

    public init(id: UUID = UUID(), kind: HealthSignalKind, availability: EvidenceAvailability<String>) {
        self.id = id
        self.kind = kind
        self.availability = availability
    }
}

public enum FindingCategory: String, Codable, Sendable {
    case connectionBottleneck
    case normalDeviceClassPerformance
    case slowSequentialWrite
    case slowSequentialRead
    case smallFileOverhead
    case filesystemLimitation
    case nearlyFull
    case thermalThrottling
    case unstableThroughput
    case possibleFailingFlash
    case readOnly
    case hubAdapter
    case insufficientPower
    case filesystemVerification
    case unavailableHealthEvidence
    case externalBottleneck
    case integrityFailure
    case ioErrors
}

public enum FindingSeverity: Int, Codable, Comparable, Sendable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct DiagnosticEvidence: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var label: String
    public var value: String

    public init(id: UUID = UUID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct DiagnosticFinding: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var category: FindingCategory
    public var severity: FindingSeverity
    public var confidence: Double
    public var explanation: String
    public var evidence: [DiagnosticEvidence]
    public var expectedImpact: String
    public var recommendedAction: String
    public var caveat: String?

    public init(id: UUID = UUID(), title: String, category: FindingCategory, severity: FindingSeverity, confidence: Double, explanation: String, evidence: [DiagnosticEvidence], expectedImpact: String, recommendedAction: String, caveat: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.severity = severity
        self.confidence = min(1, max(0, confidence))
        self.explanation = explanation
        self.evidence = evidence
        self.expectedImpact = expectedImpact
        self.recommendedAction = recommendedAction
        self.caveat = caveat
    }
}

public enum HealthClassification: String, Codable, Sendable {
    case healthy = "Healthy"
    case limitedByConnection = "Limited by connection"
    case attentionRecommended = "Attention recommended"
    case critical = "Critical"
    case inconclusive = "Inconclusive"
}

public struct AssessmentComponent: Codable, Equatable, Sendable {
    public var score: Int?
    public var confidence: Double
    public var summary: String

    public init(score: Int?, confidence: Double, summary: String) {
        self.score = score.map { min(100, max(0, $0)) }
        self.confidence = min(1, max(0, confidence))
        self.summary = summary
    }
}

public struct HealthAssessment: Codable, Equatable, Sendable {
    public var classification: HealthClassification
    public var estimatedScore: Int?
    public var confidence: Double
    public var media: AssessmentComponent
    public var performance: AssessmentComponent
    public var connection: AssessmentComponent
    public var filesystem: AssessmentComponent
    public var summary: String

    public init(classification: HealthClassification, estimatedScore: Int?, confidence: Double, media: AssessmentComponent, performance: AssessmentComponent, connection: AssessmentComponent, filesystem: AssessmentComponent, summary: String) {
        self.classification = classification
        self.estimatedScore = estimatedScore
        self.confidence = min(1, max(0, confidence))
        self.media = media
        self.performance = performance
        self.connection = connection
        self.filesystem = filesystem
        self.summary = summary
    }
}

public struct DiagnosisReport: Codable, Equatable, Sendable {
    public var assessment: HealthAssessment
    public var findings: [DiagnosticFinding]
    public var expectedPracticalRangeMBps: ClosedRange<Double>?
    public var limitations: [String]

    public init(assessment: HealthAssessment, findings: [DiagnosticFinding], expectedPracticalRangeMBps: ClosedRange<Double>?, limitations: [String]) {
        self.assessment = assessment
        self.findings = findings
        self.expectedPracticalRangeMBps = expectedPracticalRangeMBps
        self.limitations = limitations
    }
}

public struct TestSession: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var timestamp: Date
    public var driveIdentityHash: String
    public var drive: PhysicalDrive
    public var volume: Volume
    public var connection: USBConnection
    public var benchmark: BenchmarkResult?
    public var filesystemCheck: FilesystemCheckResult
    public var healthSignals: [HealthSignal]
    public var diagnosis: DiagnosisReport

    public init(id: UUID = UUID(), timestamp: Date = Date(), driveIdentityHash: String, drive: PhysicalDrive, volume: Volume, connection: USBConnection, benchmark: BenchmarkResult?, filesystemCheck: FilesystemCheckResult, healthSignals: [HealthSignal], diagnosis: DiagnosisReport) {
        self.id = id
        self.timestamp = timestamp
        self.driveIdentityHash = driveIdentityHash
        self.drive = drive
        self.volume = volume
        self.connection = connection
        self.benchmark = benchmark
        self.filesystemCheck = filesystemCheck
        self.healthSignals = healthSignals
        self.diagnosis = diagnosis
    }
}
