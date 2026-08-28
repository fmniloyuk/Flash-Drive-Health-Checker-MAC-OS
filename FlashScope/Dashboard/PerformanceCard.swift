import Charts
import FlashScopeCore
import SwiftUI

struct PerformanceCard: View {
    let benchmark: BenchmarkResult?
    let progress: BenchmarkProgress?
    let isBenchmarking: Bool
    let expectedRange: ClosedRange<Double>?
    let unit: ThroughputUnit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DiagnosticCard("Performance", systemImage: "speedometer", subtitle: "File-level sequential test with durable write flush and integrity read-back") {
            VStack(alignment: .leading, spacing: 14) {
                if isBenchmarking, let progress {
                    liveProgress(progress)
                }
                if let benchmark {
                    HStack(spacing: 12) {
                        metricTile("Write", value: benchmark.writeMegabytesPerSecond, icon: "arrow.down.to.line")
                        metricTile("Read", value: benchmark.readMegabytesPerSecond, icon: "arrow.up.from.line")
                        VStack(alignment: .leading, spacing: 5) {
                            Label(benchmark.integrity.status == .passed ? "Integrity passed" : "Integrity mismatch", systemImage: benchmark.integrity.status == .passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(benchmark.integrity.status == .passed ? .green : .red)
                            Text("SHA-256 read-back verification")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    }

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
                    .frame(height: 210)
                    .chartYAxisLabel(unit.rawValue)
                    .chartXAxisLabel("Elapsed seconds")
                    .accessibilityLabel("Sequential throughput over time")

                    HStack(alignment: .top, spacing: 20) {
                        statistics("Write statistics", benchmark.writeStatistics)
                        Divider()
                        statistics("Read statistics", benchmark.readStatistics)
                    }

                    if let small = benchmark.smallFileResult {
                        InsetNotice(kind: .info, title: "Small-file workload", message: String(format: "%.1f %@, %.0f files/s, %.0f ops/s across %d files. Small-file work is intentionally reported separately from large sequential throughput.", converted(small.megabytesPerSecond), unit.rawValue, small.filesPerSecond, small.operationsPerSecond, small.fileCount))
                    }
                    InsetNotice(kind: .info, title: "Read-cache limitation", message: "The standard read is file-level and may be influenced by macOS filesystem/RAM caching. It is never labeled as raw-media performance. Write timing includes a durable flush.")
                } else if !isBenchmarking {
                    ContentUnavailableView("No benchmark yet", systemImage: "waveform.path.ecg.rectangle", description: Text("Start a health check to measure bounded sequential read/write performance and verify the data written by FlashScope."))
                        .frame(minHeight: 130)
                }
            }
        }
        .accessibilityIdentifier("performance-card")
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
