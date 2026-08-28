import Foundation

public struct JSONReportEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "1.0"
    public var schemaVersion: String
    public var application: String
    public var applicationVersion: String
    public var reportVersion: String
    public var reportGeneratedAt: Date
    public var timezone: String
    public var device: ReportDeviceSummary
    public var volume: Volume
    public var connection: USBConnection
    public var benchmark: BenchmarkResult?
    public var filesystemCheck: FilesystemCheckResult
    public var healthSignals: [HealthSignal]
    public var diagnosis: DiagnosisReport
    public var methodology: ReportMethodology

    public init(application: String = "FlashScope", applicationVersion: String = "1.0.0", reportVersion: String = "1.0", reportGeneratedAt: Date = Date(), timezone: String, device: ReportDeviceSummary, volume: Volume, connection: USBConnection, benchmark: BenchmarkResult?, filesystemCheck: FilesystemCheckResult, healthSignals: [HealthSignal], diagnosis: DiagnosisReport, methodology: ReportMethodology) {
        self.schemaVersion = Self.currentSchemaVersion
        self.application = application
        self.applicationVersion = applicationVersion
        self.reportVersion = reportVersion
        self.reportGeneratedAt = reportGeneratedAt
        self.timezone = timezone
        self.device = device
        self.volume = volume
        self.connection = connection
        self.benchmark = benchmark
        self.filesystemCheck = filesystemCheck
        self.healthSignals = healthSignals
        self.diagnosis = diagnosis
        self.methodology = methodology
    }
}

public struct ReportDeviceSummary: Codable, Equatable, Sendable {
    public var displayName: String
    public var bsdName: String
    public var manufacturer: EvidenceAvailability<String>
    public var model: EvidenceAvailability<String>
    public var serialNumber: EvidenceAvailability<String>
    public var capacityBytes: UInt64
    public var removable: Bool
    public var external: Bool
}

public struct ReportMethodology: Codable, Equatable, Sendable {
    public var writeFlushIncluded: Bool
    public var readCacheCaveat: String
    public var integrityAlgorithm: String
    public var cleanupGuarantee: String
    public var flashWearNotice: String

    public init(writeFlushIncluded: Bool, readCacheCaveat: String, integrityAlgorithm: String, cleanupGuarantee: String, flashWearNotice: String) {
        self.writeFlushIncluded = writeFlushIncluded
        self.readCacheCaveat = readCacheCaveat
        self.integrityAlgorithm = integrityAlgorithm
        self.cleanupGuarantee = cleanupGuarantee
        self.flashWearNotice = flashWearNotice
    }
}

public struct DefaultReportGenerator: ReportGenerator {
    public var applicationVersion: String

    public init(applicationVersion: String = "1.0.0") {
        self.applicationVersion = applicationVersion
    }

    public func jsonReport(for session: TestSession, options: ReportRedactionOptions) throws -> Data {
        let envelope = envelope(for: session, options: options)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    public func plainTextReport(for session: TestSession, options: ReportRedactionOptions) -> String {
        let report = envelope(for: session, options: options)
        var lines = [
            "FlashScope Diagnostic Report",
            "Application version: \(report.applicationVersion)",
            "Report version: \(report.reportVersion)",
            "Generated: \(ISO8601DateFormatter().string(from: report.reportGeneratedAt)) (\(report.timezone))",
            "Schema: \(report.schemaVersion)",
            "",
            "Device: \(report.device.displayName)",
            "Capacity: \(StorageFormatting.bytes(report.device.capacityBytes))",
            "Volume: \(report.volume.name)",
            "Filesystem: \(report.volume.filesystem.value?.rawValue ?? "Unavailable")",
            "Mount: \(report.volume.mountPath)",
            "Health: \(report.diagnosis.assessment.classification.rawValue)",
            "Diagnostic confidence: \(Int(report.diagnosis.assessment.confidence * 100))%"
        ]
        if let speed = report.connection.negotiatedSpeed.value { lines.append("Negotiated USB speed: \(speed.label)") }
        if let benchmark = report.benchmark {
            lines += [
                "Sequential write: \(String(format: "%.1f MB/s", benchmark.writeMegabytesPerSecond))",
                "Sequential read: \(String(format: "%.1f MB/s", benchmark.readMegabytesPerSecond))",
                "Integrity: \(benchmark.integrity.status.rawValue)",
                "Cleanup: \(benchmark.cleanupStatus.rawValue)",
                "Read cache caveat: file-level read may be affected by macOS caching"
            ]
        }
        lines.append("")
        lines.append("Prioritized findings:")
        for (index, finding) in report.diagnosis.findings.enumerated() {
            lines.append("\(index + 1). \(finding.title) — \(finding.explanation)")
            lines.append("   Action: \(finding.recommendedAction)")
            if let caveat = finding.caveat { lines.append("   Caveat: \(caveat)") }
        }
        if !report.diagnosis.limitations.isEmpty {
            lines.append("")
            lines.append("Limitations:")
            lines.append(contentsOf: report.diagnosis.limitations.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private func envelope(for session: TestSession, options: ReportRedactionOptions) -> JSONReportEnvelope {
        var volume = session.volume
        if options.redactUsernamesInPaths { volume.mountPath = Self.redactUsername(in: volume.mountPath) }
        let serial: EvidenceAvailability<String> = options.redactSerialNumber ? .unavailable("Redacted by export settings") : session.drive.serialNumber
        let device = ReportDeviceSummary(
            displayName: session.drive.displayName,
            bsdName: session.drive.bsdName,
            manufacturer: session.drive.manufacturer,
            model: session.drive.model,
            serialNumber: serial,
            capacityBytes: session.drive.capacityBytes,
            removable: session.drive.isRemovable,
            external: session.drive.isExternal
        )
        return JSONReportEnvelope(
            applicationVersion: applicationVersion,
            reportVersion: JSONReportEnvelope.currentSchemaVersion,
            timezone: TimeZone.current.identifier,
            device: device,
            volume: volume,
            connection: session.connection,
            benchmark: session.benchmark,
            filesystemCheck: session.filesystemCheck,
            healthSignals: session.healthSignals,
            diagnosis: session.diagnosis,
            methodology: .init(
                writeFlushIncluded: session.benchmark?.durableFlushIncluded ?? false,
                readCacheCaveat: "Standard reads are file-level and may be affected by macOS caches. They are never labeled as raw-device performance.",
                integrityAlgorithm: "SHA-256",
                cleanupGuarantee: "Only the exact FlashScope-owned directory and file identities are eligible for deletion; symlinks and mismatched identities are rejected.",
                flashWearNotice: "The write benchmark writes the configured amount of data and therefore adds a small amount of flash wear."
            )
        )
    }

    public static func redactUsername(in path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let usersIndex = components.firstIndex(of: "Users"), usersIndex + 1 < components.count, !components[usersIndex + 1].isEmpty else { return path }
        var redacted = components
        redacted[usersIndex + 1] = "<redacted>"
        return redacted.joined(separator: "/")
    }
}
