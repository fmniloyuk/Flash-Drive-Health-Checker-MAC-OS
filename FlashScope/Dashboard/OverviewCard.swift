import FlashScopeCore
import SwiftUI

struct OverviewCard: View {
    let drive: PhysicalDrive
    let volume: Volume
    let diagnosis: DiagnosisReport?
    let connection: USBConnection
    let benchmark: BenchmarkResult?
    let filesystemCheck: FilesystemCheckResult
    let healthSignals: [HealthSignal]
    let history: [TestSession]

    var body: some View {
        DiagnosticCard("Diagnosis", systemImage: "waveform.path.ecg.rectangle", subtitle: "Verdict first — cause, confidence, and the safest next step") {
            VStack(alignment: .leading, spacing: 16) {
                hero
                Divider()
                dimensions
                Divider()
                evidenceAndAction
            }
        }
        .accessibilityIdentifier("overview-card")
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Text(drive.displayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    if let assessment = diagnosis?.assessment {
                        HealthStatusBadge(classification: assessment.classification)
                    }
                }
                Text(primaryVerdict)
                    .font(.headline)
                Text(primarySummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let comparison = localComparison {
                    Label(historyChangeText(comparison), systemImage: comparison.writeChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(abs(comparison.writeChangePercent) >= 25 ? Color.orange : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                MetricRow(label: "Capacity", value: StorageFormatting.bytes(volume.capacityBytes))
                MetricRow(label: "Free space", value: "\(StorageFormatting.bytes(volume.availableBytes)) (\(Int(volume.freeFraction * 100))%)")
                MetricRow(label: "Connection", value: connection.negotiatedSpeed.value?.label ?? "Not exposed")
                if let assessment = diagnosis?.assessment {
                    MetricRow(label: "Diagnostic confidence", value: "\(Int(assessment.confidence * 100))%", detail: "Confidence describes evidence coverage, not a drive-health percentage")
                }
            }
            .frame(minWidth: 280, idealWidth: 340)
        }
    }

    private var dimensions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
            dimensionTile(
                title: "Media reliability",
                icon: "memorychip",
                component: diagnosis?.assessment.media,
                fallback: benchmark?.integrity.status == .passed ? "No integrity failure detected" : "Needs integrity evidence"
            )
            dimensionTile(
                title: "Connection quality",
                icon: "cable.connector",
                component: diagnosis?.assessment.connection,
                fallback: connection.negotiatedSpeed.value == nil ? "Link evidence unavailable" : "Connection measured"
            )
            dimensionTile(
                title: "Filesystem",
                icon: "internaldrive",
                component: diagnosis?.assessment.filesystem,
                fallback: filesystemCheck.status == .passed ? "Verification passed" : "Verification not complete"
            )
            dimensionTile(
                title: "Performance",
                icon: "speedometer",
                component: diagnosis?.assessment.performance,
                fallback: benchmark == nil ? "Not benchmarked yet" : "Measured"
            )
        }
    }

    private func dimensionTile(title: String, icon: String, component: AssessmentComponent?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(component?.summary ?? fallback)
                .font(.callout.weight(.medium))
                .lineLimit(3)
            if let score = component?.score {
                ProgressView(value: Double(score), total: 100)
                    .accessibilityLabel("\(title) evidence-based score")
                    .accessibilityValue("\(score) out of 100")
            } else {
                Text("Insufficient evidence for a score")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
    }

    private var evidenceAndAction: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Evidence coverage", systemImage: "checklist.checked")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(coverage.availableSignals)/\(coverage.totalSignals) · \(coverage.percentage)%")
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                ProgressView(value: coverage.fraction)
                Text(coverage.missing.isEmpty ? "All tracked evidence categories are available." : "Missing: \(coverage.missing.joined(separator: ", ")). Missing evidence lowers confidence but does not by itself mean the drive is failing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended next step")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(primaryAction)
                    .font(.callout.weight(.semibold))
                if let finding = primaryFinding {
                    Text("Based on \(finding.evidence.count) evidence item\(finding.evidence.count == 1 ? "" : "s") · \(Int(finding.confidence * 100))% finding confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(benchmark == nil ? "Run a Standard check to collect performance and integrity evidence." : "No high-priority corrective action is currently indicated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 280, idealWidth: 340, alignment: .leading)
            .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var coverage: EvidenceCoverageSummary {
        DiagnosticInsightAnalyzer.evidenceCoverage(
            drive: drive,
            volume: volume,
            connection: connection,
            benchmark: benchmark,
            filesystemCheck: filesystemCheck,
            healthSignals: healthSignals
        )
    }

    private var primaryFinding: DiagnosticFinding? {
        diagnosis?.findings
            .filter { $0.severity > .info }
            .sorted {
                if $0.severity != $1.severity { return $0.severity > $1.severity }
                return $0.confidence > $1.confidence
            }
            .first
    }

    private var primaryVerdict: String {
        if let finding = primaryFinding { return finding.title }
        if benchmark == nil { return "No benchmark yet — inspection is incomplete" }
        return diagnosis?.assessment.classification.rawValue ?? "Collecting evidence"
    }

    private var primarySummary: String {
        if let finding = primaryFinding { return finding.explanation }
        return diagnosis?.assessment.summary ?? "FlashScope is collecting safe evidence from this removable drive."
    }

    private var primaryAction: String {
        primaryFinding?.recommendedAction ?? (benchmark == nil ? "Run a Standard diagnostic check." : "Keep monitoring this drive over time and retest if behavior changes.")
    }

    private var localComparison: LocalPerformanceComparison? {
        guard let benchmark else { return nil }
        let prior = history.compactMap(\.benchmark).filter { $0 != benchmark }
        return DiagnosticInsightAnalyzer.localComparison(current: benchmark, history: prior)
    }

    private func historyChangeText(_ comparison: LocalPerformanceComparison) -> String {
        let sign = comparison.writeChangePercent >= 0 ? "+" : ""
        return String(format: "Write performance %@%.0f%% vs local history", sign, comparison.writeChangePercent)
    }
}
