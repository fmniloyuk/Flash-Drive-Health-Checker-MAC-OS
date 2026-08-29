import FlashScopeCore
import SwiftUI

struct FindingsCard: View {
    let diagnosis: DiagnosisReport?
    let retestAction: () -> Void

    var body: some View {
        DiagnosticCard("What FlashScope thinks is happening", systemImage: "list.bullet.clipboard", subtitle: "Prioritized cause → impact → safe action → retest") {
            if let diagnosis {
                VStack(alignment: .leading, spacing: 12) {
                    if diagnosis.findings.isEmpty {
                        Label("No specific problem was identified from the available evidence", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(Array(diagnosis.findings.enumerated()), id: \.element.id) { index, finding in
                        findingCard(finding, rank: index + 1)
                    }
                    if !diagnosis.limitations.isEmpty {
                        DisclosureGroup("Diagnostic limitations (\(diagnosis.limitations.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(diagnosis.limitations, id: \.self) { limitation in
                                    Label(limitation, systemImage: "questionmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text("A limitation is missing evidence, not a failed health signal.")
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
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

    private func findingCard(_ finding: DiagnosticFinding, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(rank)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                Text(finding.title).font(.headline)
                Spacer()
                SeverityLabel(severity: finding.severity)
                Text("\(Int(finding.confidence * 100))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("Finding confidence \(Int(finding.confidence * 100)) percent")
            }

            Text(finding.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                explanationBlock(title: "Impact", icon: "bolt.trianglebadge.exclamationmark", text: finding.expectedImpact)
                explanationBlock(title: "What to do", icon: "wrench.and.screwdriver", text: finding.recommendedAction)
            }

            if let experiment = diagnosticExperiment(for: finding) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Diagnostic experiment", systemImage: "testtube.2")
                        .font(.caption.weight(.semibold))
                    Text(experiment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        retestAction()
                    } label: {
                        Label("Retest After the Change", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }

            if let caveat = finding.caveat {
                Text("Caveat: \(caveat)").font(.caption).foregroundStyle(.secondary)
            }

            DisclosureGroup("Evidence used") {
                VStack(spacing: 5) {
                    ForEach(finding.evidence) { evidence in
                        MetricRow(label: evidence.label, value: evidence.value)
                    }
                }.padding(.top, 5)
            }
            .font(.caption)
        }
        .padding(13)
        .background(background(for: finding.severity), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if finding.severity >= .high {
                RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.25), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func explanationBlock(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func diagnosticExperiment(for finding: DiagnosticFinding) -> String? {
        switch finding.category {
        case .connectionBottleneck, .hubAdapter:
            return "Change one thing only: disconnect intermediate hubs/adapters or move to another known high-speed port. Then rerun the same profile. If negotiated speed and throughput rise together, the original connection path was the probable cause."
        case .slowSequentialWrite, .unstableThroughput:
            return "Let the drive idle/cool, ensure at least 15% free space where practical, keep the same port, and rerun the same profile. Repeated slowdowns under similar conditions are more meaningful than a single run."
        case .nearlyFull:
            return "Move or delete unneeded files yourself, empty Trash if appropriate, refresh FlashScope, then rerun the same profile. Compare write speed before and after freeing space."
        case .insufficientPower:
            return "Connect directly to the Mac or a properly powered hub, then rerun the same profile. Improvement in stability/disconnect behavior supports a power-path explanation."
        case .smallFileOverhead:
            return "Repeat with the small-file workload enabled and compare it with sequential throughput. If sequential speed remains healthy while files/s stays low, metadata/file-count overhead is the likely cause."
        case .filesystemVerification:
            return "After backing up important data and addressing the filesystem with an appropriate macOS tool, rerun read-only verification before another write benchmark."
        default:
            return nil
        }
    }

    private func background(for severity: FindingSeverity) -> Color {
        switch severity {
        case .critical, .high: Color.red.opacity(0.06)
        case .medium: Color.orange.opacity(0.07)
        case .low: Color.yellow.opacity(0.05)
        case .info: Color.secondary.opacity(0.05)
        }
    }
}
