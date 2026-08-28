import FlashScopeCore
import SwiftUI

struct DashboardView: View {
    let model: AppViewModel
    let verifyFilesystem: () -> Void

    var body: some View {
        if let drive = model.selectedDrive, let volume = model.selectedVolume {
            ScrollView {
                LazyVStack(spacing: 16) {
                    OverviewCard(drive: drive, volume: volume, diagnosis: model.diagnosis, connection: model.connection)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], spacing: 16) {
                        ConnectionCard(drive: drive, connection: model.connection, diagnosis: model.diagnosis)
                        FilesystemCard(volume: volume, result: model.filesystemCheck, isVerifying: model.isVerifyingFilesystem, verifyAction: verifyFilesystem)
                    }

                    PerformanceCard(
                        benchmark: model.benchmarkResult,
                        progress: model.benchmarkProgress,
                        isBenchmarking: model.isBenchmarking,
                        expectedRange: model.diagnosis?.expectedPracticalRangeMBps,
                        unit: model.preferences.throughputUnit
                    )
                    FindingsCard(diagnosis: model.diagnosis)
                    HistoryCard(
                        sessions: model.history,
                        unit: model.preferences.throughputUnit,
                        delete: { session in Task { await model.deleteHistory(session) } },
                        deleteAll: { Task { await model.deleteAllHistory() } }
                    )
                }
                .padding(20)
            }
            .navigationTitle(volume.name)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            ContentUnavailableView("Inspecting drive…", systemImage: "externaldrive.badge.questionmark", description: Text("FlashScope is collecting safe read-only information about the selected removable drive."))
        }
    }
}
