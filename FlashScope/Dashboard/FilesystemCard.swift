import AppKit
import FlashScopeCore
import SwiftUI

struct FilesystemCard: View {
    let volume: Volume
    let result: FilesystemCheckResult
    let isVerifying: Bool
    let verifyAction: () -> Void
    let refreshAction: () -> Void

    var body: some View {
        DiagnosticCard("Filesystem", systemImage: "internaldrive", subtitle: "Shows detected issues with safe next steps; FlashScope never repairs automatically") {
            VStack(spacing: 9) {
                if let filesystem = volume.filesystem.value {
                    MetricRow(label: "Type", value: filesystem.rawValue)
                }
                MetricRow(label: "Free space", value: "\(StorageFormatting.bytes(volume.availableBytes)) (\(Int(volume.freeFraction * 100))%)")
                MetricRow(label: "Write state", value: volume.isReadOnly ? "Read-only" : "Writable")
                MetricRow(label: "Verification", value: verificationLabel, detail: result.exitStatus.map { "Exit status \($0)" })

                if volume.filesystem.value == .fat32 {
                    InsetNotice(
                        kind: .info,
                        title: "FAT32 compatibility note",
                        message: "FAT32 cannot store a single file of 4 GiB or larger, so FlashScope disables incompatible extended benchmarks. This is a filesystem limitation, not evidence of failing flash."
                    )
                }

                if volume.freeFraction < 0.10 {
                    InsetNotice(
                        kind: .warning,
                        title: volume.availableBytes == 0 ? "Drive is full" : "Very little free space",
                        message: volume.availableBytes == 0
                            ? "No free space is available. FlashScope cannot safely run a write benchmark until space is freed. Open the drive in Finder, remove or move files yourself, empty Trash if those files came from this drive, then refresh."
                            : "A nearly full flash drive can sustain slower writes and leaves little room for a safe benchmark. Move or remove unneeded files yourself, then refresh and retest."
                    )
                    HStack(spacing: 10) {
                        Button {
                            openVolumeInFinder()
                        } label: {
                            Label("Open Drive", systemImage: "folder")
                        }
                        .disabled(!volume.isMounted)

                        Button {
                            refreshAction()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                }

                if volume.isReadOnly {
                    InsetNotice(
                        kind: .warning,
                        title: "Volume is read-only",
                        message: "FlashScope cannot run a write benchmark while macOS reports this volume as read-only. Check hardware write protection if present, reconnect the drive, or inspect the volume in Disk Utility. FlashScope will not remount it read-write or reformat it automatically."
                    )
                    HStack(spacing: 10) {
                        Button("Open Disk Utility") { openDiskUtility() }
                        Button("Refresh") { refreshAction() }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                }

                switch result.status {
                case .issuesDetected:
                    InsetNotice(
                        kind: .critical,
                        title: "Filesystem verification reported problems",
                        message: "Back up important data before attempting repair. FlashScope only performed verification and did not change the filesystem. You can inspect the disk in Disk Utility after making a backup."
                    )
                    HStack(spacing: 10) {
                        Button("Verify Again…") { verifyAction() }
                            .disabled(isVerifying || !volume.isMounted)
                        Button("Open Disk Utility") { openDiskUtility() }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)

                case .unableToRun, .permissionDenied, .toolUnavailable:
                    InsetNotice(
                        kind: .info,
                        title: "Verification did not complete",
                        message: result.summary
                    )
                    HStack(spacing: 10) {
                        Button("Try Again…") { verifyAction() }
                            .disabled(isVerifying || !volume.isMounted)
                        Button("Open Disk Utility") { openDiskUtility() }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)

                default:
                    EmptyView()
                }

                DisclosureGroup("Compatibility guidance") {
                    VStack(alignment: .leading, spacing: 7) {
                        guidance("FAT32", "Very broad compatibility; 4 GiB single-file limit and older design.")
                        guidance("exFAT", "Broad macOS/Windows compatibility for large files; commonly used on removable media.")
                        guidance("APFS", "Modern Apple filesystem; best suited to Apple platforms and not broadly writable elsewhere.")
                        guidance("HFS+", "Legacy Apple filesystem; useful for older macOS workflows but less portable.")
                        Text("Changing filesystem normally requires destructive reformatting. Back up the drive first. FlashScope provides guidance only and never performs that action automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Disk Utility") { openDiskUtility() }
                            .controlSize(.small)
                    }
                    .padding(.top, 7)
                }

                HStack {
                    Button {
                        verifyAction()
                    } label: {
                        if isVerifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(result.status == .passed ? "Verify Again…" : "Verify Filesystem…", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(isVerifying || !volume.isMounted)
                    .accessibilityHint("Requests confirmation before a normal, non-forced unmount. No repair command is run.")
                    .accessibilityIdentifier("verify-filesystem-button")
                    Spacer()
                    Text("May require a normal unmount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private func openVolumeInFinder() {
        guard volume.isMounted else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: volume.mountPath, isDirectory: true))
    }

    private func openDiskUtility() {
        let candidates = [
            "/System/Applications/Utilities/Disk Utility.app",
            "/Applications/Utilities/Disk Utility.app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
