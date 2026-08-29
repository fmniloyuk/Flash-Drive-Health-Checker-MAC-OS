import FlashScopeCore
import SwiftUI

struct DashboardView: View {
    private enum DashboardMode: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case diagnose = "Diagnose"
        case technical = "Technical"
        var id: String { rawValue }
    }

    let model: AppViewModel
    let verifyFilesystem: () -> Void
    let retestAction: () -> Void
    @State private var mode: DashboardMode = .overview

    var body: some View {
        if let drive = model.selectedDrive, let volume = model.selectedVolume {
            ScrollView {
                LazyVStack(spacing: 16) {
                    OverviewCard(
                        drive: drive,
                        volume: volume,
                        diagnosis: model.diagnosis,
                        connection: model.connection,
                        benchmark: model.benchmarkResult,
                        filesystemCheck: model.filesystemCheck,
                        healthSignals: model.healthSignals,
                        history: model.history
                    )

                    Picker("Dashboard mode", selection: $mode) {
                        ForEach(DashboardMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("dashboard-mode-picker")

                    switch mode {
                    case .overview:
                        FindingsCard(diagnosis: model.diagnosis, retestAction: retestAction)
                        PerformanceCard(
                            benchmark: model.benchmarkResult,
                            progress: model.benchmarkProgress,
                            isBenchmarking: model.isBenchmarking,
                            expectedRange: model.diagnosis?.expectedPracticalRangeMBps,
                            unit: model.preferences.throughputUnit,
                            workload: model.preferences.workload
                        )
                        HistoryCard(
                            sessions: model.history,
                            unit: model.preferences.throughputUnit,
                            delete: { session in Task { await model.deleteHistory(session) } },
                            deleteAll: { Task { await model.deleteAllHistory() } }
                        )

                    case .diagnose:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16)], spacing: 16) {
                            ConnectionCard(
                                drive: drive,
                                connection: model.connection,
                                diagnosis: model.diagnosis,
                                refreshAction: { Task { await model.refresh() } }
                            )
                            FilesystemCard(
                                volume: volume,
                                result: model.filesystemCheck,
                                isVerifying: model.isVerifyingFilesystem,
                                verifyAction: verifyFilesystem,
                                refreshAction: { Task { await model.refresh() } }
                            )
                        }
                        FindingsCard(diagnosis: model.diagnosis, retestAction: retestAction)
                        PerformanceCard(
                            benchmark: model.benchmarkResult,
                            progress: model.benchmarkProgress,
                            isBenchmarking: model.isBenchmarking,
                            expectedRange: model.diagnosis?.expectedPracticalRangeMBps,
                            unit: model.preferences.throughputUnit,
                            workload: model.preferences.workload
                        )

                    case .technical:
                        technicalEvidence(drive: drive, volume: volume)
                        ConnectionCard(
                            drive: drive,
                            connection: model.connection,
                            diagnosis: model.diagnosis,
                            refreshAction: { Task { await model.refresh() } }
                        )
                        FilesystemCard(
                            volume: volume,
                            result: model.filesystemCheck,
                            isVerifying: model.isVerifyingFilesystem,
                            verifyAction: verifyFilesystem,
                            refreshAction: { Task { await model.refresh() } }
                        )
                        PerformanceCard(
                            benchmark: model.benchmarkResult,
                            progress: model.benchmarkProgress,
                            isBenchmarking: model.isBenchmarking,
                            expectedRange: model.diagnosis?.expectedPracticalRangeMBps,
                            unit: model.preferences.throughputUnit,
                            workload: model.preferences.workload
                        )
                        FindingsCard(diagnosis: model.diagnosis, retestAction: retestAction)
                        HistoryCard(
                            sessions: model.history,
                            unit: model.preferences.throughputUnit,
                            delete: { session in Task { await model.deleteHistory(session) } },
                            deleteAll: { Task { await model.deleteAllHistory() } }
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle(volume.name)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            ContentUnavailableView("Inspecting drive…", systemImage: "externaldrive.badge.questionmark", description: Text("FlashScope is collecting safe read-only information about the selected removable drive."))
        }
    }

    private func technicalEvidence(drive: PhysicalDrive, volume: Volume) -> some View {
        DiagnosticCard("Technical Evidence", systemImage: "terminal", subtitle: model.preferences.technicianMode ? "Technician mode — raw evidence plus conservative lab triage" : "Enable Technician mode in Settings for lab-oriented context") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        MetricRow(label: "BSD device", value: drive.bsdName)
                        MetricRow(label: "Volume BSD", value: volume.bsdName)
                        MetricRow(label: "Mount path", value: volume.mountPath)
                        MetricRow(label: "Filesystem", value: volume.filesystem.value?.rawValue ?? "Not exposed")
                        MetricRow(label: "Partition scheme", value: volume.partitionScheme.value?.rawValue ?? "Not exposed")
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 7) {
                        MetricRow(label: "VID", value: model.connection.vendorID.value.map { String(format: "0x%04X", $0) } ?? "Not exposed")
                        MetricRow(label: "PID", value: model.connection.productID.value.map { String(format: "0x%04X", $0) } ?? "Not exposed")
                        MetricRow(label: "Negotiated", value: model.connection.negotiatedSpeed.value?.label ?? "Not exposed")
                        MetricRow(label: "History records", value: "\(model.history.count)")
                        MetricRow(label: "Lab triage", value: labTriage)
                    }
                    .frame(maxWidth: .infinity)
                }

                let coverage = DiagnosticInsightAnalyzer.evidenceCoverage(
                    drive: drive,
                    volume: volume,
                    connection: model.connection,
                    benchmark: model.benchmarkResult,
                    filesystemCheck: model.filesystemCheck,
                    healthSignals: model.healthSignals
                )
                InsetNotice(
                    kind: labTriage == "FAIL" ? .critical : .info,
                    title: "Evidence coverage \(coverage.availableSignals)/\(coverage.totalSignals)",
                    message: "Available: \(coverage.available.joined(separator: ", ")). Missing: \(coverage.missing.isEmpty ? "none" : coverage.missing.joined(separator: ", ")). Lab triage is conservative and is not a certification of future reliability."
                )
            }
        }
        .accessibilityIdentifier("technical-evidence-card")
    }

    private var labTriage: String {
        guard model.preferences.technicianMode else { return "Technician mode off" }
        guard let diagnosis = model.diagnosis else { return "REVIEW" }
        if diagnosis.findings.contains(where: { $0.severity == .critical }) { return "FAIL" }
        if model.benchmarkResult?.integrity.status == .mismatch { return "FAIL" }
        if diagnosis.findings.contains(where: { $0.severity >= .high }) { return "REVIEW" }
        if model.benchmarkResult == nil { return "REVIEW" }
        return "PASS (current evidence)"
    }
}
