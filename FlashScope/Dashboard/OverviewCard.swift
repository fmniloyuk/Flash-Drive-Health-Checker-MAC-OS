import FlashScopeCore
import SwiftUI

struct OverviewCard: View {
    let drive: PhysicalDrive
    let volume: Volume
    let diagnosis: DiagnosisReport?
    let connection: USBConnection

    var body: some View {
        DiagnosticCard("Overview", systemImage: "gauge.with.dots.needle.50percent", subtitle: "Capacity, mount state, and current assessment") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(drive.displayName).font(.title3.weight(.semibold)).lineLimit(2)
                        if let assessment = diagnosis?.assessment { HealthStatusBadge(classification: assessment.classification) }
                    }
                    ProgressView(value: Double(volume.usedBytes), total: Double(max(1, volume.capacityBytes)))
                        .accessibilityLabel("Used storage")
                        .accessibilityValue("\(StorageFormatting.bytes(volume.usedBytes)) used, \(StorageFormatting.bytes(volume.availableBytes)) free")
                    HStack {
                        Text("\(StorageFormatting.bytes(volume.usedBytes)) used")
                        Spacer()
                        Text("\(StorageFormatting.bytes(volume.availableBytes)) free")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(label: "Filesystem", value: volume.filesystem.value?.rawValue ?? "Unavailable")
                    MetricRow(label: "Partition scheme", value: volume.partitionScheme.value?.rawValue ?? "Unavailable")
                    MetricRow(label: "Mount state", value: volume.isMounted ? (volume.isReadOnly ? "Mounted, read-only" : "Mounted, writable") : "Not mounted")
                    MetricRow(label: "Connection", value: connection.negotiatedSpeed.value?.label ?? "Unavailable")
                    if let assessment = diagnosis?.assessment {
                        MetricRow(label: "Diagnostic confidence", value: "\(Int(assessment.confidence * 100))%", detail: "Reduced when evidence is unavailable")
                    }
                }
                .frame(minWidth: 260, idealWidth: 320)
            }
        }
        .accessibilityIdentifier("overview-card")
    }
}
