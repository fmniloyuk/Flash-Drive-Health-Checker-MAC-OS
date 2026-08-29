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
        let coverage = DiagnosticInsightAnalyzer.evidenceCoverage(
            drive: session.drive,
            volume: session.volume,
            connection: session.connection,
            benchmark: session.benchmark,
            filesystemCheck: session.filesystemCheck,
            healthSignals: session.healthSignals
        )
        let primary = report.diagnosis.findings
            .filter { $0.severity > .info }
            .sorted {
                if $0.severity != $1.severity { return $0.severity > $1.severity }
                return $0.confidence > $1.confidence
            }
            .first

        var lines = [
            "FlashScope Diagnostic Evidence Certificate",
            "========================================",
            "Application version: \(report.applicationVersion)",
            "Report version: \(report.reportVersion)",
            "Generated: \(ISO8601DateFormatter().string(from: report.reportGeneratedAt)) (\(report.timezone))",
            "Schema: \(report.schemaVersion)",
            "",
            "VERDICT",
            "-------",
            "Classification: \(report.diagnosis.assessment.classification.rawValue)",
            "Diagnostic confidence: \(Int(report.diagnosis.assessment.confidence * 100))%",
            "Evidence coverage: \(coverage.availableSignals)/\(coverage.totalSignals) (\(coverage.percentage)%)",
            "Summary: \(report.diagnosis.assessment.summary)",
            "Primary cause: \(primary?.title ?? "No high-priority cause identified")",
            "Recommended next step: \(primary?.recommendedAction ?? "Retest if behavior changes or additional evidence becomes available.")",
            "",
            "DEVICE / VOLUME",
            "---------------",
            "Device: \(report.device.displayName)",
            "Capacity: \(StorageFormatting.bytes(report.device.capacityBytes))",
            "Volume: \(report.volume.name)",
            "Filesystem: \(report.volume.filesystem.value?.rawValue ?? "Unavailable")",
            "Partition scheme: \(report.volume.partitionScheme.value?.rawValue ?? "Unavailable")",
            "Free space: \(StorageFormatting.bytes(report.volume.availableBytes)) (\(Int(report.volume.freeFraction * 100))%)",
            "Mount: \(report.volume.mountPath)",
            "Write state: \(report.volume.isReadOnly ? "Read-only" : "Writable")",
            "",
            "CONNECTION",
            "----------",
            "Declared USB capability: \((report.connection.declaredSpecification.value ?? session.drive.capabilities.declaredUSBSpecification.value)?.rawValue ?? "Unavailable")",
            "Negotiated USB speed: \(report.connection.negotiatedSpeed.value?.label ?? "Unavailable")",
            "Hub/adapter detected: \(report.connection.hubOrAdapterDetected.value.map { $0 ? "Yes" : "No" } ?? "Unavailable")"
        ]

        if let benchmark = report.benchmark {
            let stability = DiagnosticInsightAnalyzer.stability(for: benchmark)
            lines += [
                "",
                "PERFORMANCE / INTEGRITY",
                "-----------------------",
                "Profile: \(benchmark.configuration.preset.rawValue)",
                "Temporary data written: \(StorageFormatting.bytes(benchmark.configuration.sizeBytes))",
                "Sequential write: \(String(format: "%.1f MB/s", benchmark.writeMegabytesPerSecond))",
                "Sequential read: \(String(format: "%.1f MB/s", benchmark.readMegabytesPerSecond))",
                "Stability: \(stability.label) (\(stability.score)/100)",
                "Variation: \(stability.variationPercent)%",
                "Deep stalls: \(stability.stallCount)",
                "Integrity: \(benchmark.integrity.status.rawValue)",
                "I/O errors: \(benchmark.ioErrorCount)",
                "Cleanup: \(benchmark.cleanupStatus.rawValue)",
                "Durable write flush included: \(benchmark.durableFlushIncluded ? "Yes" : "No")"
            ]
            if let cliff = DiagnosticInsightAnalyzer.cacheCliff(for: benchmark), cliff.detected {
                lines += [
                    "Write-cache cliff: detected",
                    "Burst median: \(String(format: "%.1f MB/s", cliff.burstMegabytesPerSecond))",
                    "Sustained median: \(String(format: "%.1f MB/s", cliff.sustainedMegabytesPerSecond))",
                    "Observed drop: \(cliff.dropPercent)%",
                    "Estimated cliff point: \(cliff.estimatedCliffBytes.map(StorageFormatting.bytes) ?? "Unavailable")"
                ]
            }
            if benchmark.configuration.preset == .custom {
                lines.append("Capacity-integrity note: this certificate covers the tested free-space sample only; occupied/untested capacity was not overwritten.")
            }
        } else {
            lines += ["", "PERFORMANCE / INTEGRITY", "-----------------------", "No benchmark was run in this session."]
        }

        lines += [
            "",
            "FILESYSTEM VERIFICATION",
            "-----------------------",
            "Status: \(report.filesystemCheck.status.rawValue)",
            "Summary: \(report.filesystemCheck.summary)",
            "Repair performed by FlashScope: No",
            "",
            "PRIORITIZED FINDINGS",
            "--------------------"
        ]
        if report.diagnosis.findings.isEmpty {
            lines.append("No specific findings from the available evidence.")
        } else {
            for (index, finding) in report.diagnosis.findings.enumerated() {
                lines.append("\(index + 1). [\(finding.severity)] \(finding.title) — confidence \(Int(finding.confidence * 100))%")
                lines.append("   Why: \(finding.explanation)")
                lines.append("   Impact: \(finding.expectedImpact)")
                lines.append("   Action: \(finding.recommendedAction)")
                for evidence in finding.evidence {
                    lines.append("   Evidence: \(evidence.label) = \(evidence.value)")
                }
                if let caveat = finding.caveat { lines.append("   Caveat: \(caveat)") }
            }
        }

        if !report.diagnosis.limitations.isEmpty {
            lines.append("")
            lines.append("LIMITATIONS")
            lines.append("-----------")
            lines.append(contentsOf: report.diagnosis.limitations.map { "- \($0)" })
        }

        lines += [
            "",
            "METHODOLOGY / SAFETY",
            "--------------------",
            "Read cache caveat: \(report.methodology.readCacheCaveat)",
            "Integrity algorithm: \(report.methodology.integrityAlgorithm)",
            "Cleanup guarantee: \(report.methodology.cleanupGuarantee)",
            "Flash wear notice: \(report.methodology.flashWearNotice)",
            "",
            "This certificate records evidence observed at the time of testing. It does not guarantee future reliability. Maintain independent backups of important data."
        ]

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
