import Charts
import FlashScopeCore
import SwiftUI

struct HistoryCard: View {
    let sessions: [TestSession]
    let unit: ThroughputUnit
    let delete: (TestSession) -> Void
    let deleteAll: () -> Void

    var body: some View {
        DiagnosticCard("Device Timeline", systemImage: "clock.arrow.circlepath", subtitle: "Tracks deterioration, improvement, and fix/retest outcomes for this privacy-preserving device identity") {
            if sessions.isEmpty {
                ContentUnavailableView("No history for this device", systemImage: "clock", description: Text("Completed health checks will appear here and stay on this Mac."))
                    .frame(minHeight: 110)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if let comparison = latestComparison {
                        comparisonPanel(comparison)
                    }

                    let benchmarked = sessions.filter { $0.benchmark != nil }.sorted { $0.timestamp < $1.timestamp }
                    if !benchmarked.isEmpty {
                        Chart {
                            ForEach(benchmarked) { session in
                                if let benchmark = session.benchmark {
                                    LineMark(x: .value("Date", session.timestamp), y: .value("Throughput", converted(benchmark.writeMegabytesPerSecond)))
                                        .foregroundStyle(by: .value("Series", "Write"))
                                    PointMark(x: .value("Date", session.timestamp), y: .value("Throughput", converted(benchmark.writeMegabytesPerSecond)))
                                        .foregroundStyle(by: .value("Series", "Write"))
                                    LineMark(x: .value("Date", session.timestamp), y: .value("Throughput", converted(benchmark.readMegabytesPerSecond)))
                                        .foregroundStyle(by: .value("Series", "Read"))
                                    PointMark(x: .value("Date", session.timestamp), y: .value("Throughput", converted(benchmark.readMegabytesPerSecond)))
                                        .foregroundStyle(by: .value("Series", "Read"))
                                }
                            }
                        }
                        .frame(height: 170)
                        .chartYAxisLabel(unit.rawValue)
                        .accessibilityLabel("Read and write benchmark timeline")
                    }

                    Text("Timeline")
                        .font(.callout.weight(.semibold))

                    ForEach(sessions.prefix(8)) { session in
                        timelineRow(session)
                        if session.id != sessions.prefix(8).last?.id { Divider() }
                    }

                    HStack {
                        Text("\(sessions.count) local record\(sessions.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Delete All History", role: .destructive, action: deleteAll)
                    }
                }
            }
        }
        .accessibilityIdentifier("history-card")
    }

    private func timelineRow(_ session: TestSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: session.diagnosis.assessment.classification))
                .foregroundStyle(color(for: session.diagnosis.assessment.classification))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout.weight(.medium))
                    HealthStatusBadge(classification: session.diagnosis.assessment.classification)
                }
                if let benchmark = session.benchmark {
                    Text(String(format: "Write %.1f %@  •  Read %.1f %@  •  Integrity %@", converted(benchmark.writeMegabytesPerSecond), unit.rawValue, converted(benchmark.readMegabytesPerSecond), unit.rawValue, benchmark.integrity.status.rawValue))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    let stability = DiagnosticInsightAnalyzer.stability(for: benchmark)
                    Text("Stability \(stability.label) (\(stability.score)/100) · \(benchmark.configuration.preset.rawValue.capitalized) profile")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text(session.diagnosis.assessment.summary)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Button(role: .destructive) { delete(session) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this local history record")
                .accessibilityLabel("Delete history from \(session.timestamp.formatted())")
        }
    }

    private func comparisonPanel(_ comparison: SessionDelta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Fix / retest comparison", systemImage: "arrow.triangle.swap")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(changeLabel(comparison.writePercent))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(abs(comparison.writePercent) >= 20 ? (comparison.writePercent > 0 ? Color.green : Color.orange) : Color.secondary)
            }
            HStack(spacing: 16) {
                MetricRow(label: "Previous write", value: String(format: "%.1f %@", converted(comparison.previous.writeMegabytesPerSecond), unit.rawValue))
                MetricRow(label: "Latest write", value: String(format: "%.1f %@", converted(comparison.latest.writeMegabytesPerSecond), unit.rawValue))
                MetricRow(label: "Read change", value: changeLabel(comparison.readPercent))
            }
            Text(comparisonExplanation(comparison))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private var latestComparison: SessionDelta? {
        let ordered = sessions.compactMap { session -> (Date, BenchmarkResult)? in
            session.benchmark.map { (session.timestamp, $0) }
        }.sorted { $0.0 > $1.0 }
        guard ordered.count >= 2 else { return nil }
        let latest = ordered[0].1
        let previous = ordered[1].1
        let writePercent = previous.writeMegabytesPerSecond > 0 ? (latest.writeMegabytesPerSecond / previous.writeMegabytesPerSecond - 1) * 100 : 0
        let readPercent = previous.readMegabytesPerSecond > 0 ? (latest.readMegabytesPerSecond / previous.readMegabytesPerSecond - 1) * 100 : 0
        return .init(previous: previous, latest: latest, writePercent: writePercent, readPercent: readPercent)
    }

    private func changeLabel(_ percent: Double) -> String {
        String(format: "%@%.0f%%", percent >= 0 ? "+" : "", percent)
    }

    private func comparisonExplanation(_ comparison: SessionDelta) -> String {
        if comparison.writePercent >= 25 {
            return "The latest write result improved materially. If you intentionally changed one variable—such as removing a hub, changing ports, or freeing space—this supports that change as a likely contributor."
        }
        if comparison.writePercent <= -25 {
            return "The latest write result is materially lower. Repeat under similar conditions before concluding the drive has deteriorated; port, temperature, free space, and host activity can change results."
        }
        return "The two most recent write results are in a similar range. Repeated tests under controlled conditions provide stronger evidence than a single measurement."
    }

    private func icon(for classification: HealthClassification) -> String {
        switch classification {
        case .healthy: "checkmark.circle.fill"
        case .limitedByConnection: "cable.connector"
        case .attentionRecommended: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .inconclusive: "questionmark.circle.fill"
        }
    }

    private func color(for classification: HealthClassification) -> Color {
        switch classification {
        case .healthy: .green
        case .limitedByConnection: .blue
        case .attentionRecommended: .orange
        case .critical: .red
        case .inconclusive: .secondary
        }
    }

    private func converted(_ value: Double) -> Double { StorageFormatting.throughput(value, unit: unit) }

    private struct SessionDelta {
        let previous: BenchmarkResult
        let latest: BenchmarkResult
        let writePercent: Double
        let readPercent: Double
    }
}
