import XCTest
@testable import FlashScopeCore

final class DiagnosticInsightTests: XCTestCase {
    func testEvidenceCoverageSeparatesAvailableAndMissingSignals() {
        let input = DiagnosticFixtures.healthyUSB2()
        let coverage = DiagnosticInsightAnalyzer.evidenceCoverage(
            drive: input.drive,
            volume: input.volume,
            connection: input.connection,
            benchmark: input.benchmark,
            filesystemCheck: input.filesystemCheck,
            healthSignals: input.healthSignals
        )

        XCTAssertGreaterThan(coverage.availableSignals, 0)
        XCTAssertEqual(coverage.totalSignals, 11)
        XCTAssertTrue(coverage.available.contains("Negotiated link"))
        XCTAssertTrue(coverage.available.contains("Data integrity"))
        XCTAssertTrue(coverage.missing.contains("USB power"))
        XCTAssertGreaterThan(coverage.percentage, 50)
        XCTAssertLessThanOrEqual(coverage.percentage, 100)
    }

    func testCacheCliffDetectionFindsSustainedWriteCollapse() throws {
        var benchmark = DiagnosticFixtures.makeBenchmark(read: 180, write: 70)
        let speeds: [Double] = [122, 118, 115, 108, 25, 20, 18, 17, 16]
        benchmark.configuration.sizeBytes = 9_000_000_000
        benchmark.writeSamples = speeds.enumerated().map { index, speed in
            ThroughputSample(
                elapsedSeconds: Double(index + 1) * 5,
                megabytesPerSecond: speed,
                phase: .writing
            )
        }
        benchmark.writeStatistics = StatisticsCalculator.calculate(samples: speeds)

        let analysis = try XCTUnwrap(DiagnosticInsightAnalyzer.cacheCliff(for: benchmark))
        XCTAssertTrue(analysis.detected)
        XCTAssertGreaterThan(analysis.burstMegabytesPerSecond, 100)
        XCTAssertLessThan(analysis.sustainedMegabytesPerSecond, 30)
        XCTAssertGreaterThanOrEqual(analysis.dropPercent, 70)
        XCTAssertNotNil(analysis.estimatedCliffBytes)
    }

    func testStableTransferScoresHigherThanUnstableTransfer() {
        var stable = DiagnosticFixtures.makeBenchmark(read: 100, write: 80)
        stable.writeSamples = [78, 80, 82, 79, 81, 80].enumerated().map {
            ThroughputSample(elapsedSeconds: Double($0.offset + 1), megabytesPerSecond: $0.element, phase: .writing)
        }
        stable.readSamples = [98, 100, 102, 101, 99, 100].enumerated().map {
            ThroughputSample(elapsedSeconds: Double($0.offset + 1), megabytesPerSecond: $0.element, phase: .reading)
        }

        var unstable = stable
        unstable.writeSamples = [80, 5, 82, 3, 78, 2].enumerated().map {
            ThroughputSample(elapsedSeconds: Double($0.offset + 1), megabytesPerSecond: $0.element, phase: .writing)
        }
        unstable.readSamples = [100, 4, 98, 3, 102, 2].enumerated().map {
            ThroughputSample(elapsedSeconds: Double($0.offset + 1), megabytesPerSecond: $0.element, phase: .reading)
        }
        unstable.ioErrorCount = 1

        let stableAnalysis = DiagnosticInsightAnalyzer.stability(for: stable)
        let unstableAnalysis = DiagnosticInsightAnalyzer.stability(for: unstable)

        XCTAssertGreaterThan(stableAnalysis.score, unstableAnalysis.score)
        XCTAssertEqual(stableAnalysis.label, "Excellent")
        XCTAssertGreaterThan(unstableAnalysis.stallCount, 0)
    }

    func testWorkloadSuitabilityUsesSmallFileEvidence() {
        var benchmark = DiagnosticFixtures.makeBenchmark(read: 150, write: 100)
        benchmark.smallFileResult = .init(
            totalBytes: 32_000_000,
            fileCount: 500,
            megabytesPerSecond: 8,
            filesPerSecond: 320,
            operationsPerSecond: 640
        )

        let suitability = DiagnosticInsightAnalyzer.workloadSuitability(.developerProjects, benchmark: benchmark)
        XCTAssertEqual(suitability.rating, .good)
        XCTAssertTrue(suitability.summary.contains("320"))
    }

    func testTransferEstimateUsesDecimalMegabytes() throws {
        let seconds = try XCTUnwrap(
            DiagnosticInsightAnalyzer.estimatedTransferSeconds(bytes: 1_000_000_000, megabytesPerSecond: 100)
        )
        XCTAssertEqual(seconds, 10, accuracy: 0.001)
        XCTAssertNil(DiagnosticInsightAnalyzer.estimatedTransferSeconds(bytes: 1_000_000_000, megabytesPerSecond: 0))
    }

    func testLocalComparisonReportsRegression() throws {
        let current = DiagnosticFixtures.makeBenchmark(read: 90, write: 40)
        let history = [
            DiagnosticFixtures.makeBenchmark(read: 120, write: 80),
            DiagnosticFixtures.makeBenchmark(read: 100, write: 70)
        ]

        let comparison = try XCTUnwrap(DiagnosticInsightAnalyzer.localComparison(current: current, history: history))
        XCTAssertLessThan(comparison.writeChangePercent, -40)
        XCTAssertLessThan(comparison.readChangePercent, 0)
    }

    func testTextReportIsAnEvidenceCertificateWithCoverage() {
        let input = DiagnosticFixtures.healthyUSB2()
        let diagnosis = RuleBasedDiagnosisEngine().diagnose(input)
        let session = TestSession(
            driveIdentityHash: "privacy-hash",
            drive: input.drive,
            volume: input.volume,
            connection: input.connection,
            benchmark: input.benchmark,
            filesystemCheck: input.filesystemCheck,
            healthSignals: input.healthSignals,
            diagnosis: diagnosis
        )

        let report = DefaultReportGenerator().plainTextReport(for: session, options: .init(redactSerialNumber: true, redactUsernamesInPaths: true))
        XCTAssertTrue(report.contains("FlashScope Diagnostic Evidence Certificate"))
        XCTAssertTrue(report.contains("Evidence coverage"))
        XCTAssertTrue(report.contains("METHODOLOGY / SAFETY"))
        XCTAssertFalse(report.contains("Serial:"))
    }
}
