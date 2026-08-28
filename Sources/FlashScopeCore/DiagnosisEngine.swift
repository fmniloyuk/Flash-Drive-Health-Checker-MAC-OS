import Foundation

public struct PerformanceBaseline: Codable, Equatable, Sendable {
    public var linkMbpsUpperBound: Double
    public var practicalSequentialReadMBps: ClosedRange<Double>
    public var description: String

    public init(linkMbpsUpperBound: Double, practicalSequentialReadMBps: ClosedRange<Double>, description: String) {
        self.linkMbpsUpperBound = linkMbpsUpperBound
        self.practicalSequentialReadMBps = practicalSequentialReadMBps
        self.description = description
    }
}

public struct BaselineCatalog: Codable, Equatable, Sendable {
    public var baselines: [PerformanceBaseline]

    public init(baselines: [PerformanceBaseline] = [
        .init(linkMbpsUpperBound: 500, practicalSequentialReadMBps: 20...35, description: "USB 2.0 practical large-file range"),
        .init(linkMbpsUpperBound: 5_500, practicalSequentialReadMBps: 40...450, description: "USB 3.x 5 Gb/s connection guidance"),
        .init(linkMbpsUpperBound: 11_000, practicalSequentialReadMBps: 50...900, description: "USB 3.x 10 Gb/s connection guidance"),
        .init(linkMbpsUpperBound: .greatestFiniteMagnitude, practicalSequentialReadMBps: 50...1_500, description: "High-speed USB guidance; media may be much slower than the bus")
    ]) {
        self.baselines = baselines.sorted { $0.linkMbpsUpperBound < $1.linkMbpsUpperBound }
    }

    public func expectedRange(for speed: USBLinkSpeed?) -> ClosedRange<Double>? {
        guard let speed else { return nil }
        return baselines.first(where: { speed.megabitsPerSecond <= $0.linkMbpsUpperBound })?.practicalSequentialReadMBps
    }
}

public struct RuleBasedDiagnosisEngine: DiagnosisEngine {
    public var baselines: BaselineCatalog

    public init(baselines: BaselineCatalog = .init()) {
        self.baselines = baselines
    }

    public func diagnose(_ input: DiagnosisInput) -> DiagnosisReport {
        var findings: [DiagnosticFinding] = []
        var limitations: [String] = []
        var evidenceConfidence = 1.0
        let speed = input.connection.negotiatedSpeed.value
        let range = baselines.expectedRange(for: speed)
        let declared = input.connection.declaredSpecification.value ?? input.drive.capabilities.declaredUSBSpecification.value
        let benchmark = input.benchmark

        if input.volume.isReadOnly {
            findings.append(.init(
                title: "Volume is read-only",
                category: .readOnly,
                severity: .medium,
                confidence: 0.99,
                explanation: "FlashScope cannot run a write benchmark because macOS reports this volume as read-only.",
                evidence: [.init(label: "Volume state", value: "Read-only")],
                expectedImpact: "Writes and normal file transfers to the drive are unavailable.",
                recommendedAction: "Check any hardware write-protection control and the filesystem/mount state. Do not reformat solely on this finding."
            ))
        }


        if let allocated = input.connection.allocatedMilliAmps.value,
           let available = input.connection.availableMilliAmps.value,
           allocated > available {
            findings.append(.init(
                title: "Available USB power may be insufficient",
                category: .insufficientPower,
                severity: .medium,
                confidence: 0.88,
                explanation: "The reported USB power requirement exceeds the bus power macOS reports as available on this path.",
                evidence: [
                    .init(label: "Requested/allocated power", value: "\(allocated) mA"),
                    .init(label: "Available bus power", value: "\(available) mA")
                ],
                expectedImpact: "An under-powered device or hub path can disconnect, reset, or transfer unreliably.",
                recommendedAction: "Connect the drive directly to the Mac or use a properly powered hub, then retest.",
                caveat: "USB power properties are controller-reported signals and may not be exposed consistently on every Mac or adapter."
            ))
        }

        if input.volume.freeFraction < 0.10 {
            findings.append(.init(
                title: "The device is nearly full",
                category: .nearlyFull,
                severity: .medium,
                confidence: 0.98,
                explanation: "Low free space can reduce flash write performance and leaves less room for controller housekeeping.",
                evidence: [.init(label: "Free space", value: String(format: "%.1f%%", input.volume.freeFraction * 100))],
                expectedImpact: "Sustained writes may slow down or become less stable.",
                recommendedAction: "Back up and remove unneeded data if practical, then retest."
            ))
        }

        if let benchmark {
            if benchmark.integrity.status == .mismatch {
                findings.append(.init(
                    title: "Benchmark data integrity mismatch",
                    category: .integrityFailure,
                    severity: .critical,
                    confidence: 1.0,
                    explanation: "Data read back from the benchmark file did not match what FlashScope wrote.",
                    evidence: [.init(label: "Integrity check", value: "SHA-256 mismatch")],
                    expectedImpact: "This can indicate unreliable storage, connection errors, or corruption.",
                    recommendedAction: "Back up important data immediately and stop relying on this drive until the cause is understood."
                ))
            }
            if benchmark.ioErrorCount > 0 {
                findings.append(.init(
                    title: "I/O errors occurred during testing",
                    category: .ioErrors,
                    severity: benchmark.ioErrorCount > 1 ? .critical : .high,
                    confidence: 0.99,
                    explanation: "The operating system reported input/output errors while accessing the benchmark file.",
                    evidence: [.init(label: "I/O errors", value: "\(benchmark.ioErrorCount)")],
                    expectedImpact: "Transfers can stall, fail, or produce corrupted data.",
                    recommendedAction: "Back up important data immediately, try a direct port/cable path, and retire the drive if errors repeat."
                ))
            }

            if let speed, speed.megabitsPerSecond <= 500 {
                let usb3Capable = declared == .usb3 || declared == .usb4
                if usb3Capable {
                    findings.append(.init(
                        title: "The device is connected at a reduced link speed",
                        category: .connectionBottleneck,
                        severity: .medium,
                        confidence: 0.95,
                        explanation: "The device reports USB 3.x-or-newer capability, but the current negotiated link is in the USB 2.0 speed class.",
                        evidence: [
                            .init(label: "Declared capability", value: declared?.rawValue ?? "Unavailable"),
                            .init(label: "Negotiated link", value: speed.label)
                        ],
                        expectedImpact: "Large sequential transfers are capped near USB 2.0 practical throughput regardless of faster flash media.",
                        recommendedAction: "Reconnect directly to another known USB 3-capable port, remove hubs/adapters where possible, and inspect the connector/cable path."
                    ))
                    if input.connection.hubOrAdapterDetected.value == true {
                        findings.append(.init(
                            title: "A hub or adapter is present in the USB path",
                            category: .hubAdapter,
                            severity: .low,
                            confidence: 0.86,
                            explanation: "FlashScope detected a hub or adapter in the topology while the device is operating at a reduced link speed.",
                            evidence: [.init(label: "USB topology", value: "Hub/adapter detected")],
                            expectedImpact: "The intermediate connection may be contributing to reduced negotiation speed.",
                            recommendedAction: "Retest the drive directly on a known high-speed Mac port to isolate the intermediate device.",
                            caveat: "Topology correlation does not prove that the hub or adapter is defective."
                        ))
                    }
                } else if benchmark.readMegabytesPerSecond >= 15 && benchmark.readMegabytesPerSecond <= 40 {
                    findings.append(.init(
                        title: "Performance is limited by the USB 2.0 connection/device",
                        category: .normalDeviceClassPerformance,
                        severity: .low,
                        confidence: 0.92,
                        explanation: "Measured large-file throughput is plausible for a USB 2.0 link. Slow transfers alone are not evidence that the flash media is failing.",
                        evidence: [
                            .init(label: "Negotiated link", value: speed.label),
                            .init(label: "Sequential read", value: String(format: "%.1f MB/s", benchmark.readMegabytesPerSecond)),
                            .init(label: "Sequential write", value: String(format: "%.1f MB/s", benchmark.writeMegabytesPerSecond))
                        ],
                        expectedImpact: "The connection class is the main ceiling for large sequential copies.",
                        recommendedAction: "For materially higher throughput, use a USB 3.x-capable drive and a compatible high-speed port."
                    ))
                }
            }

            if let speed, speed.megabitsPerSecond > 1_000 {
                let readLooksNormal = benchmark.readMegabytesPerSecond >= 40
                if readLooksNormal && benchmark.writeMegabytesPerSecond < 20 {
                    findings.append(.init(
                        title: "The flash write path is the probable bottleneck",
                        category: .slowSequentialWrite,
                        severity: .medium,
                        confidence: 0.84,
                        explanation: "The negotiated link and read speed are substantially faster than sustained writes, so the bus itself is unlikely to be the primary limit.",
                        evidence: [
                            .init(label: "Negotiated link", value: speed.label),
                            .init(label: "Sequential read", value: String(format: "%.1f MB/s", benchmark.readMegabytesPerSecond)),
                            .init(label: "Sequential write", value: String(format: "%.1f MB/s", benchmark.writeMegabytesPerSecond))
                        ],
                        expectedImpact: "Copying data onto the drive can be much slower than reading from it.",
                        recommendedAction: "Retest with adequate free space after the device cools. Low-end NAND, depleted write cache, controller behavior, or aging media are possibilities; this result alone does not prove failure."
                    ))
                }
            }

            if benchmark.writeStatistics.coefficientOfVariation > 0.45 || benchmark.readStatistics.coefficientOfVariation > 0.45 {
                findings.append(.init(
                    title: "Throughput is unusually unstable",
                    category: .unstableThroughput,
                    severity: .medium,
                    confidence: 0.8,
                    explanation: "Transfer speed varied substantially during the sequential test.",
                    evidence: [
                        .init(label: "Write variation", value: String(format: "%.0f%%", benchmark.writeStatistics.coefficientOfVariation * 100)),
                        .init(label: "Read variation", value: String(format: "%.0f%%", benchmark.readStatistics.coefficientOfVariation * 100))
                    ],
                    expectedImpact: "Real file copies may pause or alternate between fast and slow periods.",
                    recommendedAction: "Retest after cooling the device and without a hub. Repeated stalls combined with I/O errors should be treated seriously.",
                    caveat: "Variation can also reflect flash-cache exhaustion or host activity; FlashScope does not infer thermal throttling without temperature evidence."
                ))
            }

            if let small = benchmark.smallFileResult, benchmark.writeMegabytesPerSecond > 0, small.megabytesPerSecond < benchmark.writeMegabytesPerSecond * 0.20 {
                findings.append(.init(
                    title: "Small-file overhead is the likely slowdown",
                    category: .smallFileOverhead,
                    severity: .low,
                    confidence: 0.92,
                    explanation: "Large sequential transfers are healthy relative to the connection, while the many-file workload is much slower because each file adds metadata and filesystem operations.",
                    evidence: [
                        .init(label: "Large-file write", value: String(format: "%.1f MB/s", benchmark.writeMegabytesPerSecond)),
                        .init(label: "Small-file workload", value: String(format: "%.1f MB/s, %.0f files/s", small.megabytesPerSecond, small.filesPerSecond))
                    ],
                    expectedImpact: "Folders containing thousands of small files can copy many times slower than one large file.",
                    recommendedAction: "When appropriate, archive many small files into a single container before transfer, then extract them at the destination."
                ))
            }

            if !input.historicalBenchmarks.isEmpty {
                let priorWrites = input.historicalBenchmarks.map(\.writeMegabytesPerSecond)
                let baseline = priorWrites.reduce(0, +) / Double(priorWrites.count)
                if baseline > 0 && benchmark.writeMegabytesPerSecond < baseline * 0.60 {
                    findings.append(.init(
                        title: "Write performance regressed versus local history",
                        category: .slowSequentialWrite,
                        severity: .medium,
                        confidence: 0.82,
                        explanation: "The latest sustained write result is more than 40% below the local historical average for this privacy-preserving device identity.",
                        evidence: [
                            .init(label: "Current write", value: String(format: "%.1f MB/s", benchmark.writeMegabytesPerSecond)),
                            .init(label: "Historical average", value: String(format: "%.1f MB/s", baseline))
                        ],
                        expectedImpact: "The device or its connection may now perform worse than it previously did.",
                        recommendedAction: "Repeat the test on a direct port under similar conditions before drawing a hardware conclusion."
                    ))
                }
            }
        }

        switch input.filesystemCheck.status {
        case .issuesDetected:
            findings.append(.init(
                title: "Filesystem verification reported problems",
                category: .filesystemVerification,
                severity: .high,
                confidence: 0.95,
                explanation: "A read-only filesystem verification completed and reported issues.",
                evidence: [.init(label: "Verification", value: input.filesystemCheck.summary)],
                expectedImpact: "Filesystem problems can cause errors, stalls, or inaccessible files.",
                recommendedAction: "Back up important data before considering repair with an appropriate tool. FlashScope never repairs automatically."
            ))
        case .unableToRun:
            findings.append(.init(
                title: "Filesystem verification could not run",
                category: .filesystemVerification,
                severity: .info,
                confidence: 1.0,
                explanation: "The verification did not complete, so FlashScope cannot classify the filesystem as passed or damaged.",
                evidence: [.init(label: "Verification", value: input.filesystemCheck.summary)],
                expectedImpact: "Filesystem health remains unknown.",
                recommendedAction: "Close open files and Finder windows for the volume, then try verification again if desired."
            ))
            limitations.append("Filesystem verification did not run to completion.")
        case .permissionDenied, .toolUnavailable:
            limitations.append("Filesystem verification evidence is unavailable: \(input.filesystemCheck.summary)")
            evidenceConfidence -= 0.08
        default: break
        }

        let smartSignal = input.healthSignals.first(where: { $0.kind == .smart })?.availability
            ?? input.drive.capabilities.supportsSMART.mapToString()
        switch smartSignal {
        case .unsupported, .unavailable, .permissionDenied, .failed:
            findings.append(.init(
                title: "Hardware health evidence is unavailable",
                category: .unavailableHealthEvidence,
                severity: .info,
                confidence: 1.0,
                explanation: "SMART or equivalent media-health data is not supported or not exposed through this USB bridge/controller.",
                evidence: [.init(label: "SMART", value: "Not supported or not exposed")],
                expectedImpact: "FlashScope has less evidence about underlying media health.",
                recommendedAction: "Interpret benchmark and integrity results with this limitation in mind.",
                caveat: "Missing SMART is not a SMART failure."
            ))
            limitations.append("SMART or equivalent hardware-health data is not available through the current USB path.")
            evidenceConfidence -= 0.12
        case .available: break
        }

        if input.connection.negotiatedSpeed.value == nil {
            limitations.append("Negotiated USB link speed is unavailable; connection diagnosis confidence is reduced.")
            evidenceConfidence -= 0.18
        }
        if input.connection.declaredSpecification.value == nil && input.drive.capabilities.declaredUSBSpecification.value == nil {
            limitations.append("The device USB specification is unavailable.")
            evidenceConfidence -= 0.08
        }
        if benchmark == nil {
            limitations.append("No performance benchmark was run.")
            evidenceConfidence -= 0.20
        }

        findings.sort {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.confidence > $1.confidence
        }

        let assessment = score(input: input, findings: findings, confidence: max(0.2, evidenceConfidence))
        return DiagnosisReport(assessment: assessment, findings: findings, expectedPracticalRangeMBps: range, limitations: limitations)
    }

    private func score(input: DiagnosisInput, findings: [DiagnosticFinding], confidence: Double) -> HealthAssessment {
        var mediaScore: Int? = input.benchmark == nil ? nil : 92
        var performanceScore: Int? = input.benchmark == nil ? nil : 90
        var connectionScore: Int? = input.connection.negotiatedSpeed.value == nil ? nil : 92
        var filesystemScore: Int? = input.filesystemCheck.status == .notRun ? nil : 94

        for finding in findings {
            switch finding.category {
            case .integrityFailure:
                mediaScore = min(mediaScore ?? 100, 10); performanceScore = min(performanceScore ?? 100, 20)
            case .ioErrors:
                mediaScore = min(mediaScore ?? 100, 20); performanceScore = min(performanceScore ?? 100, 30)
            case .connectionBottleneck:
                connectionScore = min(connectionScore ?? 100, 55)
            case .hubAdapter:
                connectionScore = min(connectionScore ?? 100, 72)
            case .insufficientPower:
                connectionScore = min(connectionScore ?? 100, 50)
            case .slowSequentialWrite, .slowSequentialRead, .unstableThroughput:
                performanceScore = min(performanceScore ?? 100, 60)
            case .nearlyFull:
                performanceScore = min(performanceScore ?? 100, 72)
            case .filesystemVerification:
                if input.filesystemCheck.status == .issuesDetected { filesystemScore = min(filesystemScore ?? 100, 35) }
            case .readOnly:
                filesystemScore = min(filesystemScore ?? 100, 55)
            default: break
            }
        }

        // Unsupported SMART intentionally does not reduce media score; it reduces confidence only.
        let scores = [mediaScore, performanceScore, connectionScore, filesystemScore].compactMap { $0 }
        let overall = scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        let critical = findings.contains { $0.severity == .critical }
        let hasAttention = findings.contains { $0.severity >= .medium }
        let connectionLimited = findings.contains { $0.category == .normalDeviceClassPerformance || $0.category == .connectionBottleneck }
        let classification: HealthClassification
        let summary: String
        if critical {
            classification = .critical
            summary = "Critical evidence was observed. Back up important data immediately."
        } else if hasAttention {
            classification = .attentionRecommended
            summary = "One or more findings deserve attention, but the evidence does not automatically prove device failure."
        } else if connectionLimited {
            classification = .limitedByConnection
            summary = "The measured behavior is primarily explained by the current USB connection class."
        } else if input.benchmark != nil {
            classification = .healthy
            summary = "No critical integrity or I/O problems were observed in the available evidence."
        } else {
            classification = .inconclusive
            summary = "There is not enough evidence for a confident performance and media-health assessment."
        }

        return HealthAssessment(
            classification: classification,
            estimatedScore: overall,
            confidence: confidence,
            media: .init(score: mediaScore, confidence: input.benchmark == nil ? 0.35 : confidence, summary: mediaScore == nil ? "Not assessed" : "Estimated from integrity and I/O evidence"),
            performance: .init(score: performanceScore, confidence: input.benchmark == nil ? 0.2 : confidence, summary: performanceScore == nil ? "Not assessed" : "Estimated from measured throughput and stability"),
            connection: .init(score: connectionScore, confidence: input.connection.negotiatedSpeed.value == nil ? 0.25 : confidence, summary: connectionScore == nil ? "Negotiated speed unavailable" : "Estimated from negotiated link and topology evidence"),
            filesystem: .init(score: filesystemScore, confidence: input.filesystemCheck.status == .notRun ? 0.25 : confidence, summary: filesystemScore == nil ? "Verification not run" : "Estimated from mount state and verification evidence"),
            summary: summary
        )
    }
}

private extension EvidenceAvailability where Value == Bool {
    func mapToString() -> EvidenceAvailability<String> {
        switch self {
        case let .available(value): .available(value ? "Supported" : "Not supported")
        case let .unavailable(reason): .unavailable(reason)
        case let .unsupported(reason): .unsupported(reason)
        case let .permissionDenied(reason): .permissionDenied(reason)
        case let .failed(reason): .failed(reason)
        }
    }
}
