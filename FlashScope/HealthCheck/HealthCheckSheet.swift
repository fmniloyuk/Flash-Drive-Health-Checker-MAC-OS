import FlashScopeCore
import SwiftUI

struct HealthCheckSheet: View {
    let model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var preset: BenchmarkPreset
    @State private var customMiB: Double
    @State private var includeSmallFiles: Bool

    init(model: AppViewModel) {
        self.model = model
        let suggested = model.suggestedBenchmarkConfiguration()
        _preset = State(initialValue: suggested?.preset ?? .quick)
        _customMiB = State(initialValue: Double((suggested?.sizeBytes ?? BenchmarkPreset.quick.defaultBytes) / 1_048_576))
        _includeSmallFiles = State(initialValue: model.preferences.includeSmallFileTest)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Health Check").font(.title2.weight(.semibold))
                    Text("Preflight and benchmark confirmation").foregroundStyle(.secondary)
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
                        benchmarkOptions(volume: volume)
                        wearNotice(volume: volume)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Label("No existing file is overwritten", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start Test — Write \(StorageFormatting.bytes(selectedBytes))") {
                    let config = BenchmarkConfiguration(
                        preset: preset,
                        sizeBytes: selectedBytes,
                        sampleIntervalSeconds: model.preferences.sampleInterval,
                        dataPattern: .deterministicPseudoRandom,
                        includeSmallFileWorkload: includeSmallFiles
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
        .frame(minWidth: 620, idealWidth: 680, minHeight: 650)
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
                MetricRow(label: "Other-process activity", value: "Not reliably attributable", detail: "FlashScope stays non-privileged and will report write/unmount blockers if macOS encounters them")
                if volume.freeFraction < 0.10 {
                    InsetNotice(kind: .warning, title: "Nearly full", message: "Low free space can reduce flash write performance and limits the safe benchmark size.")
                }
                if volume.isReadOnly {
                    InsetNotice(kind: .warning, title: "Read-only volume", message: "The write benchmark will be skipped. Read-only inspection remains available.")
                }
            }.padding(.top, 6)
        }
    }

    private func benchmarkOptions(volume: Volume) -> some View {
        GroupBox("2. Benchmark size") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(BenchmarkPreset.allCases, id: \.self) { item in
                    if item != .custom {
                        Toggle(isOn: Binding(get: { preset == item }, set: { if $0 { preset = item } })) {
                            HStack {
                                Text(item.rawValue.capitalized).frame(width: 80, alignment: .leading)
                                Text(StorageFormatting.bytes(item.defaultBytes)).foregroundStyle(.secondary)
                                Spacer()
                                if item == .extended && volume.filesystem.value == .fat32 { Text("Unavailable on FAT32").font(.caption).foregroundStyle(.orange) }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(item == .extended && (volume.filesystem.value == .fat32 || item.defaultBytes > maxSafeBytes))
                    }
                }
                Toggle(isOn: Binding(get: { preset == .custom }, set: { if $0 { preset = .custom } })) { Text("Custom") }.toggleStyle(.checkbox)
                if preset == .custom {
                    HStack {
                        TextField("MiB", value: $customMiB, format: .number.precision(.fractionLength(0)))
                            .frame(width: 110)
                        Text("MiB")
                        Slider(value: $customMiB, in: 32...max(32, Double(maxSafeBytes / 1_048_576)), step: 16)
                    }
                }
                Divider()
                Toggle("Include optional small-file workload", isOn: $includeSmallFiles)
                Text("Disabled by default because it creates many bounded filesystem operations. It reports files/s, ops/s, and throughput separately.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
    }

    private func wearNotice(volume: Volume) -> some View {
        GroupBox("3. What the test does") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Creates a unique app-owned temporary directory and never overwrites an existing path.", systemImage: "folder.badge.plus")
                Label("Writes \(StorageFormatting.bytes(selectedBytes)) of non-zero pseudo-random data and includes durable flush time.", systemImage: "arrow.down.doc")
                Label("Reads the file back, measures sequential read throughput, and verifies SHA-256 integrity.", systemImage: "checkmark.shield")
                Label("Deletes only the exact file, ownership marker, and directory after identity/symlink validation, then verifies cleanup.", systemImage: "trash.slash")
                Text("Flash wear: this test writes approximately \(StorageFormatting.bytes(selectedBytes)) once. That is a small but real amount of flash wear.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.top, 6)
        }
    }

    private var selectedBytes: UInt64 {
        if preset == .custom { return UInt64(max(32, customMiB)) * 1_048_576 }
        return preset.defaultBytes
    }
    private var maxSafeBytes: UInt64 { model.selectedVolume.map(model.maximumSafeBenchmarkBytes(for:)) ?? 0 }
    private var canStart: Bool {
        guard let drive = model.selectedDrive, let volume = model.selectedVolume else { return false }
        return drive.isExternal && drive.isRemovable && !drive.isInternal && volume.isMounted && !volume.isReadOnly && selectedBytes <= maxSafeBytes && selectedBytes >= 32 * 1_024 * 1_024 && !(volume.filesystem.value == .fat32 && selectedBytes >= 4 * 1_024 * 1_024 * 1_024)
    }
}
