import FlashScopeCore
import SwiftUI

struct FindingsCard: View {
    let diagnosis: DiagnosisReport?

    var body: some View {
        DiagnosticCard("Findings", systemImage: "list.bullet.clipboard", subtitle: "Prioritized by severity, confidence, and evidence") {
            if let diagnosis {
                VStack(alignment: .leading, spacing: 12) {
                    if diagnosis.findings.isEmpty {
                        Label("No specific findings from the available evidence", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(diagnosis.findings) { finding in
                        findingRow(finding)
                        if finding.id != diagnosis.findings.last?.id { Divider() }
                    }
                    if !diagnosis.limitations.isEmpty {
                        DisclosureGroup("Diagnostic limitations (\(diagnosis.limitations.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(diagnosis.limitations, id: \.self) { limitation in
                                    Label(limitation, systemImage: "questionmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.top, 7)
                        }
                    }
                }
            } else {
                Text("Select and inspect a drive to generate findings.").foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("findings-card")
    }

    private func findingRow(_ finding: DiagnosticFinding) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.title).font(.callout.weight(.semibold))
                Spacer()
                SeverityLabel(severity: finding.severity)
                Text("\(Int(finding.confidence * 100))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("Confidence \(Int(finding.confidence * 100)) percent")
            }
            Text(finding.explanation).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.right.circle").foregroundStyle(.tint).accessibilityHidden(true)
                Text(finding.recommendedAction).font(.caption)
            }
            if let caveat = finding.caveat {
                Text("Caveat: \(caveat)").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Evidence") {
                VStack(spacing: 5) {
                    ForEach(finding.evidence) { evidence in
                        MetricRow(label: evidence.label, value: evidence.value)
                    }
                }.padding(.top, 5)
            }
            .font(.caption)
        }
        .accessibilityElement(children: .contain)
    }
}
