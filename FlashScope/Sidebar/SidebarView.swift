import FlashScopeCore
import SwiftUI

struct SidebarView: View {
    let model: AppViewModel

    var body: some View {
        List(selection: selection) {
            Section("Removable USB Storage") {
                ForEach(model.drives) { drive in
                    DriveSidebarRow(drive: drive, selected: model.selectedDriveID == drive.id)
                        .tag(drive.id)
                        .accessibilityIdentifier("sidebar-drive-\(drive.id)")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("FlashScope")
        .safeAreaInset(edge: .bottom) {
            if model.simulationMode {
                Label("Simulation Mode", systemImage: "testtube.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                    .accessibilityIdentifier("simulation-mode-banner")
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedDriveID },
            set: { id in
                guard let id, let drive = model.drives.first(where: { $0.id == id }) else { return }
                Task { await model.selectDrive(drive) }
            }
        )
    }
}

private struct DriveSidebarRow: View {
    let drive: PhysicalDrive
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.displayName).lineLimit(1)
                Text(StorageFormatting.bytes(drive.capacityBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if !drive.isRemovable {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                    .help("Not reported as removable; write benchmarks are disabled")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(drive.displayName), \(StorageFormatting.bytes(drive.capacityBytes)), removable USB drive")
    }
}
