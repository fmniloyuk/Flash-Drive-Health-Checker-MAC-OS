import Charts
import FlashScopeCore
import SwiftUI

struct PerformanceCard: View {
    let benchmark: BenchmarkResult?
    let progress: BenchmarkProgress?
    let isBenchmarking: Bool
    let expectedRange: ClosedRange<Double>?
    let unit: ThroughputUnit
    let workload: StorageWorkload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DiagnosticCard("Performance", systemImage: "speedometer", subtitle: "Interprets measured speed, stability, cache behavior, workload fit, and transfer time") {
            VStack(alignment: .leading, spacing: 14) {
                if isBenchmarking, let progress {
                    liveProgress(progress)
                }
                if let benchmark {
                    headlineMetrics(benchmark)
                    measuredVsExpected(benchmark)
                    throughputChart(benchmark)
                    derivedInsights(benchmark)
                    detailedStatistics(benchmark)
                    limitations(benchmark)
                } else if !isBenchmarking {
                    ContentUnavailableView("No benchmark yet", systemImage: "waveform.path.ecg.rectangle", description: Text("Run a Standard check to measure bounded sequential read/write performance, stability, and SHA-256 integrity."))
                        .frame(minHeight: 130)
                }
            }
        }
        .accessibilityIdentifier("performance-card")
    }

    private func headlineMetrics(_ benchmark: BenchmarkResult) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            metricTile("Sustained write", value: benchmark.writeMegabytesPerSecond, icon: "arrow.down.to.line")
            metricTile("Sequential read", value: benchmark.readMegabytesPerSecond, icon: "arrow.up.from.line")

            let stability = DiagnosticInsightAnalyzer.stability(for: benchmark)
            VStack(alignment: .leading, spacing: 5) {
                Label("Transfer stability", systemImage: "waveform.path")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(stability.label) · \(stability.score)/100")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(stability.variationPercent)% variation · \(stability.stallCount) deep stall\(stability.stallCount == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Label(benchmark.integrity.status == .passed ? "Integrity passed" : "Integrity mismatch", systemImage: benchmark.integrity.status == .passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(benchmark.integrity.status == .passed ? .green : .red)
                Text("SHA-256 complete read-back")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func measuredVsExpected(_ benchmark: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Measured vs expected")
                .font(.callout.weight(.semibold))
            if let expectedRange {
                comparisonRow(title: "Read", measured: benchmark.readMegabytesPerSecond, expected: expectedRange)
                let writeGuidance = max(5, expectedRange.lowerBound * 0.35)...max(15, expectedRange.upperBound * 0.70)
                comparisonRow(title: "Write", measured: benchmark.writeMegabytesPerSecond, expected: writeGuidance)
                Text("Expected ranges are diagnostic guidance based on the current connection class, not manufacturer promises. Flash media may legitimately be slower than the bus.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("FlashScope cannot anchor performance to the current USB link because negotiated-speed evidence is unavailable. The raw measurements remain valid, but bottleneck confidence is lower.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func comparisonRow(title: String, measured: Double, expected: ClosedRange<Double>) -> some View {
        let status: String
        let icon: String
        if measured < expected.lowerBound * 0.70 {
            status = "Below guidance"
            icon = "exclamationmark.triangle.fill"
        } else if measured <= expected.upperBound * 1.25 {
            status = "Plausible for this connection"
            icon = "checkmark.circle.fill"
        } else {
            status = "Above generic guidance"
            icon = "arrow.up.circle.fill"
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f %@", converted(measured), unit.rawValue)).font(.caption.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: min(1, measured / max(expected.upperBound, measured)))
            HStack {
                Label(status, systemImage: icon).font(.caption2)
                Spacer()
                Text(String(format: "Guidance %.0f–%.0f MB/s", expected.lowerBound, expected.upperBound)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func throughputChart(_ benchmark: BenchmarkResult) -> some View {
        Chart {
            ForEach(benchmark.writeSamples) { sample in
                LineMark(x: .value("Time", sample.elapsedSeconds), y: .value("Throughput", converted(sample.megabytesPerSecond)))
                    .foregroundStyle(by: .value("Series", "Write"))
            }
            ForEach(benchmark.readSamples) { sample in
                LineMark(x: .value("Time", sample.elapsedSeconds), y: .value("Throughput", converted(sample.megabytesPerSecond)))
                    .foregroundStyle(by: .value("Series", "Read"))
            }
            if let expectedRange {
                RuleMark(y: .value("Expected minimum", converted(expectedRange.lowerBound))).lineStyle(.init(dash: [4, 4])).foregroundStyle(.secondary)
                RuleMark(y: .value("Expected upper", converted(expectedRange.upperBound))).lineStyle(.init(dash: [4, 4])).foregroundStyle(.secondary)
            }
        }
        .frame(height: 220)
        .chartYAxisLabel(unit.rawValue)
        .chartXAxisLabel("Elapsed seconds")
        .accessibilityLabel("Sequential throughput over time")
    }

    @ViewBuilder
    private func derivedInsights(_ benchmark: BenchmarkResult) -> some View {
        let suitability = DiagnosticInsightAnalyzer.workloadSuitability(workload, benchmark: benchmark)
        InsetNotice(
            kind: suitability.rating == .poor ? .warning : .info,
            title: "\(workload.rawValue): \(suitability.rating.rawValue)",
            message: suitability.summary
        )

        if let cliff = DiagnosticInsightAnalyzer.cacheCliff(for: benchmark), cliff.detected {
            let location = cliff.estimatedCliffBytes.map { " after approximately \(StorageFormatting.bytes($0))" } ?? " during the sustained write"
            InsetNotice(
                kind: .warning,
                title: "Write-cache cliff detected",
                message: String(format: "Write throughput started around %.1f MB/s and settled near %.1f MB/s, a %d%% drop%@. This pattern is more consistent with burst/cache exhaustion or sustained-media limits than with the USB bus alone.", cliff.burstMegabytesPerSecond, cliff.sustainedMegabytesPerSecond, cliff.dropPercent, location)
            )
        }

        transferTimePanel(benchmark)

        if benchmark.configuration.preset == .custom {
            InsetNotice(
                kind: benchmark.integrity.status == .passed ? .info : .critical,
                title: "Capacity integrity sample",
                message: benchmark.integrity.status == .passed
                    ? "FlashScope successfully wrote and verified \(StorageFormatting.bytes(benchmark.configuration.sizeBytes)) of app-owned temporary data. This strengthens confidence in the tested free-space sample, but does not prove occupied or otherwise untested capacity."
                    : "The capacity sample did not read back identically. Treat this as critical integrity evidence and back up important data immediately."
            )
        }
    }

    private func transferTimePanel(_ benchmark: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated copy time at measured sustained write speed")
                .font(.callout.weight(.semibold))
            HStack(spacing: 10) {
                transferEstimate("1 GB", bytes: 1_000_000_000, benchmark: benchmark)
                transferEstimate("10 GB", bytes: 10_000_000_000, benchmark: benchmark)
                transferEstimate("100 GB", bytes: 100_000_000_000, benchmark: benchmark)
            }
            Text("Real copies vary with file size, filesystem metadata, source speed, caching, and other system activity.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func transferEstimate(_ label: String, bytes: UInt64, benchmark: BenchmarkResult) -> some View {
        let seconds = DiagnosticInsightAnalyzer.estimatedTransferSeconds(bytes: bytes, megabytesPerSecond: benchmark.writeMegabytesPerSecond)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(seconds.map(StorageFormatting.duration) ?? "—")
                .font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
    }

    private func detailedStatistics(_ benchmark: BenchmarkResult) -> some View {
        HStack(alignment: .top, spacing: 20) {
            statistics("Write statistics", benchmark.writeStatistics)
            Divider()
            statistics("Read statistics", benchmark.readStatistics)
        }
    }

    @ViewBuilder
    private func limitations(_ benchmark: BenchmarkResult) -> some View {
        if let small = benchmark.smallFileResult {
            InsetNotice(kind: .info, title: "Small-file workload", message: String(format: "%.1f %@, %.0f files/s, %.0f ops/s across %d files. Small-file work is intentionally reported separately from large sequential throughput.", converted(small.megabytesPerSecond), unit.rawValue, small.filesPerSecond, small.operationsPerSecond, small.fileCount))
        }
        InsetNotice(kind: .info, title: "Read-cache limitation", message: "The standard read is file-level and may be influenced by macOS filesystem/RAM caching. It is never labeled as raw-media performance. Write timing includes a durable flush.")
    }

    private func liveProgress(_ progress: BenchmarkProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(progress.phase.rawValue.capitalized, systemImage: "waveform.path")
                    .font(.callout.weight(.semibold))
                Spacer()
                if let rate = progress.currentMegabytesPerSecond {
                    Text(String(format: "%.1f %@", converted(rate), unit.rawValue)).monospacedDigit()
                }
            }
            ProgressView(value: progress.fraction)
            Text(progress.message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(11)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: progress.fraction)
        .accessibilityIdentifier("benchmark-progress")
    }

    private func metricTile(_ title: String, value: Double, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f %@", converted(value), unit.rawValue))
                .font(.title2.weight(.semibold)).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func statistics(_ title: String, _ stats: BenchmarkStatistics) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("Min \(format(stats.minimum))  •  Avg \(format(stats.average))  •  Median \(format(stats.median))")
            Text("p95 \(format(stats.p95))  •  Max \(format(stats.maximum))  •  Variation \(Int(stats.coefficientOfVariation * 100))%")
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func converted(_ decimalMBps: Double) -> Double { StorageFormatting.throughput(decimalMBps, unit: unit) }
    private func format(_ value: Double) -> String { String(format: "%.1f", converted(value)) }
}
