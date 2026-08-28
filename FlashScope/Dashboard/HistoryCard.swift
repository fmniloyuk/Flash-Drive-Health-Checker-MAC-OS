import Charts
import FlashScopeCore
import SwiftUI

struct HistoryCard: View {
    let sessions: [TestSession]
    let unit: ThroughputUnit
    let delete: (TestSession) -> Void
    let deleteAll: () -> Void

    var body: some View {
        DiagnosticCard("History", systemImage: "clock.arrow.circlepath", subtitle: "Stored locally using a privacy-preserving device identity") {
            if sessions.isEmpty {
                ContentUnavailableView("No history for this device", systemImage: "clock", description: Text("Completed health checks will appear here and stay on this Mac."))
                    .frame(minHeight: 110)
            } else {
                VStack(alignment: .leading, spacing: 12) {
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
                        .frame(height: 160)
                        .chartYAxisLabel(unit.rawValue)
                        .accessibilityLabel("Read and write benchmark history")
                    }
                    ForEach(sessions.prefix(6)) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.callout.weight(.medium))
                                if let benchmark = session.benchmark {
                                    Text(String(format: "Write %.1f %@  •  Read %.1f %@", converted(benchmark.writeMegabytesPerSecond), unit.rawValue, converted(benchmark.readMegabytesPerSecond), unit.rawValue))
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                } else {
                                    Text(session.diagnosis.assessment.classification.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { delete(session) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Delete this local history record")
                                .accessibilityLabel("Delete history from \(session.timestamp.formatted())")
                        }
                    }
                    HStack {
                        Text("\(sessions.count) local record\(sessions.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Delete All History", role: .destructive, action: deleteAll)
                    }
                }
            }
        }
        .accessibilityIdentifier("history-card")
    }

    private func converted(_ value: Double) -> Double { StorageFormatting.throughput(value, unit: unit) }
}
