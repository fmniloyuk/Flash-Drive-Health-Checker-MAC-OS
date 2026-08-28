import FlashScopeCore
import SwiftUI

struct FilesystemCard: View {
    let volume: Volume
    let result: FilesystemCheckResult
    let isVerifying: Bool
    let verifyAction: () -> Void

    var body: some View {
        DiagnosticCard("Filesystem", systemImage: "internaldrive", subtitle: "Read-only verification is optional and never repairs") {
            VStack(spacing: 9) {
                MetricRow(label: "Type", value: volume.filesystem.value?.rawValue ?? "Unavailable")
                MetricRow(label: "Free space", value: "\(StorageFormatting.bytes(volume.availableBytes)) (\(Int(volume.freeFraction * 100))%)")
                MetricRow(label: "Write state", value: volume.isReadOnly ? "Read-only" : "Writable")
                MetricRow(label: "Verification", value: verificationLabel, detail: result.exitStatus.map { "Exit status \($0)" })

                if volume.filesystem.value == .fat32 {
                    InsetNotice(kind: .warning, title: "FAT32 single-file limit", message: "FAT32 cannot store a single file of 4 GiB or larger. Extended 4 GiB benchmarks are therefore disabled on FAT32. This is a filesystem limitation, not evidence of failing flash.")
                }
                if volume.freeFraction < 0.10 {
                    InsetNotice(kind: .warning, title: "Very little free space", message: "A nearly full flash drive can sustain slower writes. Freeing space may help, but FlashScope will never reformat the volume automatically.")
                }

                DisclosureGroup("Compatibility guidance") {
                    VStack(alignment: .leading, spacing: 7) {
                        guidance("FAT32", "Very broad compatibility; 4 GiB single-file limit and older design.")
                        guidance("exFAT", "Broad macOS/Windows compatibility for large files; commonly used on removable media.")
                        guidance("APFS", "Modern Apple filesystem; best suited to Apple platforms and not broadly writable elsewhere.")
                        guidance("HFS+", "Legacy Apple filesystem; useful for older macOS workflows but less portable.")
                        Text("Changing filesystem normally requires destructive reformatting. FlashScope provides guidance only and does not perform that action.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 7)
                }

                HStack {
                    Button {
                        verifyAction()
                    } label: {
                        if isVerifying { ProgressView().controlSize(.small) } else { Label("Verify Filesystem…", systemImage: "checkmark.shield") }
                    }
                    .disabled(isVerifying || !volume.isMounted)
                    .accessibilityHint("Requests confirmation before a normal, non-forced unmount. No repair command is run.")
                    .accessibilityIdentifier("verify-filesystem-button")
                    Spacer()
                    Text("May require a normal unmount")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("filesystem-card")
    }

    private var verificationLabel: String {
        switch result.status {
        case .passed: "Passed"
        case .issuesDetected: "Issues detected"
        case .unableToRun: "Could not run"
        case .permissionDenied: "Permission denied"
        case .toolUnavailable: "Tool unavailable"
        case .cancelled: "Cancelled"
        case .notRun: "Not run"
        }
    }

    private func guidance(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).frame(width: 48, alignment: .leading)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
