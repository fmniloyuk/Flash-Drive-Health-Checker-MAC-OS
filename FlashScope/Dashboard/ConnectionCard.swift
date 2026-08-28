import AppKit
import FlashScopeCore
import SwiftUI

struct ConnectionCard: View {
    let drive: PhysicalDrive
    let connection: USBConnection
    let diagnosis: DiagnosisReport?
    let refreshAction: () -> Void

    var body: some View {
        DiagnosticCard("Connection", systemImage: "cable.connector", subtitle: "Visualizes the USB path and highlights the most likely bottleneck") {
            VStack(alignment: .leading, spacing: 14) {
                connectionPathVisualizer

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 8) {
                    if let specification {
                        MetricRow(label: "Device USB capability", value: specification.rawValue)
                    }
                    if let speed = connection.negotiatedSpeed.value {
                        MetricRow(label: "Negotiated link", value: speed.label, detail: speed.classLabel)
                        MetricRow(label: "Theoretical bus ceiling", value: String(format: "%.1f MB/s", speed.theoreticalMegabytesPerSecond))
                    }
                    if let range = diagnosis?.expectedPracticalRangeMBps {
                        MetricRow(label: "Expected practical read", value: String(format: "%.0f–%.0f MB/s", range.lowerBound, range.upperBound), detail: "Guidance, not a guarantee")
                    }
                    if let port = connection.portPath.value {
                        MetricRow(label: "USB location", value: port)
                    }
                    if let identifiers {
                        MetricRow(label: "Vendor / Product ID", value: identifiers)
                    }
                    if let power {
                        MetricRow(label: "Power", value: power)
                    }
                }

                if isReducedUSB3Link {
                    InsetNotice(
                        kind: .warning,
                        title: "Bottleneck: USB 3-capable device is running at USB 2-class speed",
                        message: "The connection is the strongest current explanation for reduced large-file throughput. Reconnect directly to a known high-speed port and remove hubs/adapters where practical, then retest."
                    )
                    recoveryActions(includeSystemInformation: true)
                } else if hasLimitedConnectionEvidence {
                    InsetNotice(
                        kind: .info,
                        title: "Some connection evidence is hidden by macOS or the USB bridge",
                        message: connectionLimitationMessage
                    )
                    recoveryActions(includeSystemInformation: true)
                } else if let speed = connection.negotiatedSpeed.value {
                    InsetNotice(
                        kind: .info,
                        title: "Connection classified",
                        message: "FlashScope can see a \(speed.label) negotiated link. Performance results should be interpreted relative to this current connection rather than the device's marketing maximum."
                    )
                }

                if !connection.topology.isEmpty {
                    DisclosureGroup("Raw USB topology") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(connection.topology) { node in
                                Label(
                                    node.name,
                                    systemImage: node.kind.localizedCaseInsensitiveContains("hub")
                                        ? "point.3.connected.trianglepath.dotted"
                                        : "circle.dotted"
                                )
                                .font(.caption)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if !missingEvidenceReasons.isEmpty {
                    DisclosureGroup("Why some connection details are missing") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(missingEvidenceReasons, id: \.self) { reason in
                                Label(reason, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Missing connection telemetry lowers diagnostic confidence, but it is not itself a drive-health failure.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
            }
        }
        .accessibilityIdentifier("connection-card")
    }

    private var connectionPathVisualizer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection path")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                pathNode(title: "Mac", detail: "USB host", icon: "laptopcomputer", warning: false)
                pathArrow

                if connection.hubOrAdapterDetected.value == true {
                    pathNode(title: "Hub / adapter", detail: "Intermediate path", icon: "point.3.connected.trianglepath.dotted", warning: isReducedUSB3Link)
                    pathArrow
                }

                pathNode(
                    title: connection.negotiatedSpeed.value?.label ?? "Link unknown",
                    detail: connection.negotiatedSpeed.value?.classLabel ?? "Negotiated speed not exposed",
                    icon: "cable.connector",
                    warning: isReducedUSB3Link || connection.negotiatedSpeed.value == nil
                )
                pathArrow
                pathNode(
                    title: drive.displayName,
                    detail: specification?.rawValue ?? "USB capability not exposed",
                    icon: "externaldrive.fill",
                    warning: false
                )
            }
            .accessibilityElement(children: .contain)

            if isReducedUSB3Link {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                    Text(connection.hubOrAdapterDetected.value == true ? "Retest without the intermediate device to isolate this path." : "Try another known high-speed port to isolate the connection.")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 11))
    }

    private func pathNode(title: String, detail: String, icon: String, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(warning ? Color.orange : Color.accentColor)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(warning ? Color.orange.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            if warning {
                RoundedRectangle(cornerRadius: 9).stroke(Color.orange.opacity(0.45), lineWidth: 1)
            }
        }
    }

    private var pathArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var specification: USBSpecification? {
        connection.declaredSpecification.value ?? drive.capabilities.declaredUSBSpecification.value
    }

    private var identifiers: String? {
        guard connection.vendorID.value != nil || connection.productID.value != nil else { return nil }
        let vendor = connection.vendorID.value.map { String(format: "0x%04X", $0) } ?? "—"
        let product = connection.productID.value.map { String(format: "0x%04X", $0) } ?? "—"
        return "\(vendor) / \(product)"
    }

    private var power: String? {
        let allocated = connection.allocatedMilliAmps.value.map { "\($0) mA requested" }
        let available = connection.availableMilliAmps.value.map { "\($0) mA available" }
        let values = [allocated, available].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private var hasLimitedConnectionEvidence: Bool {
        specification == nil || connection.negotiatedSpeed.value == nil
    }

    private var connectionLimitationMessage: String {
        if specification == nil && connection.negotiatedSpeed.value == nil {
            return "FlashScope found the removable disk, but macOS or its USB bridge did not provide enough descriptor/link information to classify the connection. Refresh, reconnect directly to the Mac, remove intermediate hubs/adapters where practical, or compare the USB entry in System Information."
        }
        if connection.negotiatedSpeed.value == nil {
            return "The device was identified, but macOS did not expose a negotiated link speed FlashScope can classify. Refresh after reconnecting directly to the Mac, or compare the USB entry in System Information."
        }
        return "The current link speed is available, but the device's declared USB specification was not exposed. FlashScope will not infer a capability from a marketing name."
    }

    private var missingEvidenceReasons: [String] {
        var reasons: [String] = []
        if specification == nil {
            reasons.append(connection.declaredSpecification.explanation ?? drive.capabilities.declaredUSBSpecification.explanation ?? "USB specification was not exposed")
        }
        if connection.negotiatedSpeed.value == nil, let reason = connection.negotiatedSpeed.explanation { reasons.append(reason) }
        if connection.vendorID.value == nil, let reason = connection.vendorID.explanation { reasons.append(reason) }
        if connection.productID.value == nil, let reason = connection.productID.explanation { reasons.append(reason) }
        if connection.portPath.value == nil, let reason = connection.portPath.explanation { reasons.append(reason) }
        if connection.allocatedMilliAmps.value == nil, let reason = connection.allocatedMilliAmps.explanation { reasons.append(reason) }
        if connection.availableMilliAmps.value == nil, let reason = connection.availableMilliAmps.explanation { reasons.append(reason) }
        return Array(Set(reasons)).sorted()
    }

    private var isReducedUSB3Link: Bool {
        guard specification == .usb3 || specification == .usb4,
              let speed = connection.negotiatedSpeed.value else { return false }
        return speed.megabitsPerSecond <= 500
    }

    @ViewBuilder
    private func recoveryActions(includeSystemInformation: Bool) -> some View {
        HStack(spacing: 10) {
            Button { refreshAction() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            if includeSystemInformation {
                Button { openSystemInformation() } label: { Label("System Information", systemImage: "info.circle") }
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }

    private func openSystemInformation() {
        let candidates = [
            "/System/Applications/Utilities/System Information.app",
            "/Applications/Utilities/System Information.app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
