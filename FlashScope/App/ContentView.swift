import FlashScopeCore
import SwiftUI

struct ContentView: View {
    let model: AppViewModel
    @State private var showHealthCheck = false
    @State private var showHelp = false
    @State private var showVerificationConfirmation = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            if model.drives.isEmpty && !model.isRefreshing {
                emptyState
            } else if model.selectedDrive != nil {
                DashboardView(
                    model: model,
                    verifyFilesystem: { showVerificationConfirmation = true },
                    retestAction: { showHealthCheck = true }
                )
            } else {
                ContentUnavailableView("Select a USB drive", systemImage: "externaldrive", description: Text("Choose a removable USB storage device from the sidebar."))
            }
        }
        .toolbar { toolbar }
        .task { await model.start() }
        .sheet(isPresented: $showHealthCheck) { HealthCheckSheet(model: model) }
        .sheet(isPresented: $showHelp) { HelpView() }
        .confirmationDialog(
            "Verify the filesystem?",
            isPresented: $showVerificationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unmount Normally and Verify") { Task { await model.verifyFilesystemAfterConfirmation() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Close files and Finder windows using this volume. FlashScope will request a normal, non-forced unmount, run read-only verification only, and attempt to remount. It will not repair the filesystem.")
        }
        .alert(item: Binding(get: { model.notice }, set: { model.notice = $0 })) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No removable USB drives", systemImage: "externaldrive.badge.plus")
        } description: {
            Text("Connect a USB flash drive. FlashScope will inspect it without modifying data until you explicitly start a diagnostic check.")
        } actions: {
            Button("Refresh") { Task { await model.refresh() } }
                .accessibilityIdentifier("empty-refresh-button")
        }
        .accessibilityIdentifier("empty-state")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(model.isRefreshing)
                .help("Refresh removable USB drives")
                .accessibilityIdentifier("refresh-button")

            if model.isBenchmarking {
                Button(role: .cancel) { model.cancelBenchmark() } label: { Label("Cancel Test", systemImage: "stop.circle") }
                    .accessibilityIdentifier("cancel-benchmark-button")
            } else {
                Button { showHealthCheck = true } label: { Label("Run Check", systemImage: "stethoscope") }
                    .disabled(model.suggestedBenchmarkConfiguration() == nil)
                    .help("Choose Quick, Standard, Deep, or Capacity Integrity diagnostics")
                    .accessibilityIdentifier("health-check-button")
            }

            Menu {
                Button("PDF Evidence Report…") { export(.pdf) }
                Button("JSON Diagnostic Report…") { export(.json) }
                Button("Text Evidence Certificate…") { export(.text) }
                Divider()
                Button("Copy Support Certificate") { copySummary() }
                if model.preferences.anonymousIntelligenceOptIn {
                    Button("Copy Anonymous Baseline Contribution") { copyAnonymousContribution() }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(model.currentSession() == nil)
            .accessibilityIdentifier("export-menu")

            Button { Task { await model.safeEjectSelectedDrive() } } label: { Label("Eject", systemImage: "eject") }
                .disabled(model.selectedDrive == nil || model.isBenchmarking)
                .help("Safely eject the selected drive")

            SettingsLink { Label("Settings", systemImage: "gearshape") }
            Button { showHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
        }
    }

    private func export(_ format: ReportExportController.Format) {
        guard let session = model.currentSession() else { return }
        do { try ReportExportController.export(session: session, format: format, reports: model.services.reports, redactIdentifiers: model.preferences.redactIdentifiers) }
        catch { model.notice = .init(title: "Export failed", message: error.localizedDescription) }
    }

    private func copySummary() {
        guard let session = model.currentSession() else { return }
        ReportExportController.copySupportSummary(session: session, reports: model.services.reports, redactIdentifiers: model.preferences.redactIdentifiers)
        model.notice = .init(title: "Support certificate copied", message: "A redacted plain-text diagnostic evidence certificate is on the clipboard.")
    }

    private func copyAnonymousContribution() {
        guard let session = model.currentSession() else { return }
        do {
            try ReportExportController.copyAnonymousContribution(session: session)
            model.notice = .init(title: "Anonymous contribution copied", message: "The privacy-minimized baseline payload is on the clipboard. FlashScope did not upload it anywhere.")
        } catch {
            model.notice = .init(title: "Couldn’t prepare contribution", message: error.localizedDescription)
        }
    }
}
