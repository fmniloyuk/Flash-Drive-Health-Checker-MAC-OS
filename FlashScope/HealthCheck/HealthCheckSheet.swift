import FlashScopeCore
import SwiftUI

struct HealthCheckSheet: View {
    private enum CheckMode: String, CaseIterable, Identifiable {
        case quick = "Quick"
        case standard = "Standard"
        case deep = "Deep"
        case capacity = "Capacity Integrity"

        var id: String { rawValue }
        var preset: BenchmarkPreset {
            switch self {
            case .quick: .quick
            case .standard: .standard
            case .deep: .extended
            case .capacity: .custom
            }
        }
        var icon: String {
            switch self {
            case .quick: "bolt"
            case .standard: "checkmark.shield"
            case .deep: "waveform.path.ecg"
            case .capacity: "externaldrive.badge.checkmark"
            }
        }
        var summary: String {
            switch self {
            case .quick: "Fast connection + integrity sample. Best for first-pass troubleshooting."
            case .standard: "Balanced sequential read/write, SHA-256 verification, and optional small-file workload."
            case .deep: "Longer sustained test intended to expose instability and write-cache slowdowns."
            case .capacity: "Uses the largest currently safe free-space sample to look for capacity/integrity problems without overwriting existing files."
            }
        }
    }

    let model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: CheckMode
    @State private var includeSmallFiles: Bool

    init(model: AppViewModel) {
        self.model = model
        let suggested = model.suggestedBenchmarkConfiguration()
        let initialMode: CheckMode
        switch suggested?.preset {
        case .quick: initialMode = .quick
        case .extended: initialMode = .deep
        default: initialMode = .standard
        }
        _mode = State(initialValue: initialMode)
        _includeSmallFiles = State(initialValue: model.preferences.includeSmallFileTest)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Run Diagnostic Check").font(.title2.weight(.semibold))
                    Text("Choose how much evidence FlashScope should collect").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let drive = model.selectedDrive, let volume = model.selectedVolume {
                        preflight(drive: drive, volume: volume)
                        modeSelector(volume: volume)
                        testPlan(volume: volume)
                        safetyNotice(volume: volume)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Label("Existing user files are never overwritten", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(startButtonTitle) {
                    let config = BenchmarkConfiguration(
                        preset: mode.preset,
                        sizeBytes: selectedBytes,
                        sampleIntervalSeconds: model.preferences.sampleInterval,
                        dataPattern: .deterministicPseudoRandom,
                        includeSmallFileWorkload: includeSmallFiles && mode != .capacity
                    )
                    model.startHealthCheck(configuration: config)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
                .accessibilityHint("Creates one unique FlashScope-owned temporary benchmark workspace on the selected removable volume, writes the stated amount, flushes, reads it back, verifies SHA-256, then performs exact cleanup.")
                .accessibilityIdentifier("confirm-start-benchmark-button")
            }
            .padding(16)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 720)
        .accessibilityIdentifier("health-check-sheet")
    }

    private func preflight(drive: PhysicalDrive, volume: Volume) -> some View {
        GroupBox("1. Preflight") {
            VStack(spacing: 8) {
                MetricRow(label: "Physical device", value: drive.displayName, detail: drive.bsdName)
                MetricRow(label: "Volume", value: volume.name, detail: volume.mountPath)
                MetricRow(label: "Capacity", value: StorageFormatting.bytes(volume.capacityBytes))
                MetricRow(label: "Available", value: "\(StorageFormatting.bytes(volume.availableBytes)) (\(Int(volume.freeFraction * 100))%)")
                MetricRow(label: "Filesystem", value: volume.filesystem.value?.rawValue ?? "Unavailable")
                MetricRow(label: "Target validation", value: drive.isExternal && drive.isRemovable && !drive.isInternal ? "External + removable" : "Not eligible")
                if volume.freeFraction < 0.10 {
                    InsetNotice(kind: .warning, title: "Nearly full", message: "Low free space can reduce flash write performance and limits every safe diagnostic profile.")
                }
                if volume.isReadOnly {
                    InsetNotice(kind: .warning, title: "Read-only volume", message: "Write-based checks cannot run while macOS reports this volume as read-only.")
                }
            }.padding(.top, 6)
        }
    }

    private func modeSelector(volume: Volume) -> some View {
        GroupBox("2. Diagnostic profile") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Diagnostic profile", selection: $mode) {
                    ForEach(CheckMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("diagnostic-profile-picker")

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: mode.icon)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(mode.rawValue).font(.headline)
                        Text(mode.summary).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Label("Writes \(StorageFormatting.bytes(selectedBytes))", systemImage: "arrow.down.doc")
                            Label("Estimated \(estimatedDuration)", systemImage: "clock")
                        }
                        .font(.caption)
                    }
                }

                if mode == .capacity {
                    InsetNotice(
                        kind: .warning,
                        title: "Capacity verification is intentionally non-destructive",
                        message: capacityExplanation(volume: volume)
                    )
                }

                if mode != .capacity {
                    Toggle("Include small-file workload", isOn: $includeSmallFiles)
                    Text("Useful for developer projects, document folders, and workloads with thousands of small files. It performs additional bounded filesystem operations and reports files/s separately from sequential throughput.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 6)
        }
    }

    private func testPlan(volume: Volume) -> some View {
        GroupBox("3. What FlashScope will measure") {
            VStack(alignment: .leading, spacing: 8) {
                planRow("Connection context", "Uses the currently exposed USB specification, negotiated link, topology, hub/adapter, and power evidence.")
                planRow("Sustained write", mode == .quick ? "Short bounded write sample." : "Tracks throughput over time so cache cliffs and stalls can be distinguished from peak speed.")
                planRow("Durable flush", "Includes a durable synchronization step before readback.")
                planRow("Sequential read", "Measures file-level read throughput and labels macOS cache influence as a limitation.")
                planRow("Integrity", "Computes SHA-256 while writing and compares it with the complete readback.")
                if includeSmallFiles && mode != .capacity {
                    planRow("Small files", "Runs a bounded mixed-size file workload and reports files/s and ops/s.")
                }
                if mode == .capacity {
                    planRow("Capacity coverage", "Verifies the largest safe sample of currently free space permitted by FlashScope's benchmark safety limit. Occupied areas are never overwritten.")
                }
            }
            .padding(.top, 6)
        }
    }

    private func safetyNotice(volume: Volume) -> some View {
        GroupBox("4. Safety & wear") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Creates a unique app-owned temporary directory and never overwrites an existing path.", systemImage: "folder.badge.plus")
                Label("Writes non-zero pseudo-random data, verifies readback, then removes only exact app-owned file identities.", systemImage: "checkmark.shield")
                Label("Cancellation and drive-removal paths use the same guarded cleanup rules.", systemImage: "xmark.shield")
                Text("Flash wear: this profile writes approximately \(StorageFormatting.bytes(selectedBytes)) once. The capacity profile can write substantially more than Standard or Deep, so use it when you specifically need stronger free-space integrity evidence.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if volume.filesystem.value == .fat32 && mode == .capacity {
                    Text("FAT32 limits a single file to under 4 GB, so capacity coverage is necessarily partial in this build. FlashScope will never reformat the volume merely to increase test coverage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.top, 6)
        }
    }

    private func planRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var selectedBytes: UInt64 {
        guard let volume = model.selectedVolume else { return 0 }
        let safe = model.maximumSafeBenchmarkBytes(for: volume)
        let fat32Limit: UInt64 = 3_800_000_000
        switch mode {
        case .quick:
            return min(BenchmarkPreset.quick.defaultBytes, safe)
        case .standard:
            return min(BenchmarkPreset.standard.defaultBytes, safe)
        case .deep:
            let target = min(BenchmarkPreset.extended.defaultBytes, safe)
            return volume.filesystem.value == .fat32 ? min(target, fat32Limit) : target
        case .capacity:
            return volume.filesystem.value == .fat32 ? min(safe, fat32Limit) : safe
        }
    }

    private var estimatedDuration: String {
        let referenceRate = max(10, model.benchmarkResult?.writeMegabytesPerSecond ?? model.history.compactMap(\.benchmark).first?.writeMegabytesPerSecond ?? 30)
        let write = DiagnosticInsightAnalyzer.estimatedTransferSeconds(bytes: selectedBytes, megabytesPerSecond: referenceRate) ?? 0
        let read = DiagnosticInsightAnalyzer.estimatedTransferSeconds(bytes: selectedBytes, megabytesPerSecond: max(referenceRate, 40)) ?? 0
        return StorageFormatting.duration((write + read) * 1.15)
    }

    private var startButtonTitle: String {
        mode == .capacity
            ? "Start Capacity Sample — Write \(StorageFormatting.bytes(selectedBytes))"
            : "Start \(mode.rawValue) Check — Write \(StorageFormatting.bytes(selectedBytes))"
    }

    private func capacityExplanation(volume: Volume) -> String {
        let fraction = volume.availableBytes == 0 ? 0 : Int((Double(selectedBytes) / Double(volume.availableBytes) * 100).rounded())
        return "FlashScope will temporarily write and verify \(StorageFormatting.bytes(selectedBytes)), about \(fraction)% of the currently free space permitted by its safety policy. Existing files and occupied regions are untouched. Passing this sample increases confidence in the tested free area; it does not prove untested occupied capacity."
    }

    private var canStart: Bool {
        guard let drive = model.selectedDrive, let volume = model.selectedVolume else { return false }
        return drive.isExternal && drive.isRemovable && !drive.isInternal && volume.isMounted && !volume.isReadOnly && selectedBytes <= model.maximumSafeBenchmarkBytes(for: volume) && selectedBytes >= 32 * 1_024 * 1_024 && !(volume.filesystem.value == .fat32 && selectedBytes >= 4_000_000_000)
    }
}
