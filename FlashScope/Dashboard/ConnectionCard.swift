import AppKit
import FlashScopeCore
import SwiftUI

struct ConnectionCard: View {
    let drive: PhysicalDrive
    let connection: USBConnection
    let diagnosis: DiagnosisReport?
    let refreshAction: () -> Void

    var body: some View {
        DiagnosticCard("Connection", systemImage: "cable.connector", subtitle: "Shows only connection evidence macOS exposes safely") {
            VStack(spacing: 9) {
                if let specification {
                    MetricRow(label: "Device USB specification", value: specification.rawValue)
                }
                if let speed = connection.negotiatedSpeed.value {
                    MetricRow(label: "Negotiated link", value: speed.label, detail: speed.classLabel)
                    MetricRow(label: "Theoretical bus ceiling", value: String(format: "%.1f MB/s bus maximum", speed.theoreticalMegabytesPerSecond))
                }
                if let range = diagnosis?.expectedPracticalRangeMBps {
                    MetricRow(label: "Expected practical read range", value: String(format: "%.0f–%.0f MB/s guidance", range.lowerBound, range.upperBound))
                }
                if let port = connection.portPath.value {
                    MetricRow(label: "USB location", value: port)
                }
                if let pathDescription {
                    MetricRow(label: "Connection path", value: pathDescription)
                }
                if let identifiers {
                    MetricRow(label: "Vendor / Product ID", value: identifiers)
                }
                if let power {
                    MetricRow(label: "Power allocation", value: power)
                }

                if isReducedUSB3Link {
                    InsetNotice(
                        kind: .warning,
                        title: "USB 3-capable device is running at USB 2-class speed",
                        message: "Reconnect the drive directly to a known high-speed port and remove hubs/adapters where practical. Then refresh FlashScope. A reduced link is a connection bottleneck, not proof of failing flash memory."
                    )
                    recoveryActions(includeSystemInformation: true)
                } else if hasLimitedConnectionEvidence {
                    InsetNotice(
                        kind: .info,
                        title: "Some USB connection telemetry is not exposed",
                        message: connectionLimitationMessage
                    )
                    recoveryActions(includeSystemInformation: true)
                }

                if !connection.topology.isEmpty {
                    DisclosureGroup("USB topology") {
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

    private var specification: USBSpecification? {
        connection.declaredSpecification.value ?? drive.capabilities.declaredUSBSpecification.value
    }

    private var pathDescription: String? {
        switch connection.hubOrAdapterDetected {
        case .available(true): return "Hub or adapter detected"
        case .available(false): return "No hub detected in exposed topology"
        default: return nil
        }
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
            return "FlashScope found the removable disk, but macOS or its USB bridge did not provide enough USB descriptor/link information to classify the connection. Try Refresh, reconnect directly to the Mac, remove intermediate hubs/adapters, or inspect the device in System Information."
        }
        if connection.negotiatedSpeed.value == nil {
            return "The device was identified, but macOS did not expose a negotiated link speed FlashScope can classify. Refresh after reconnecting directly to the Mac, or compare the USB entry in System Information."
        }
        return "The current link speed is available, but the device's declared USB specification was not exposed. FlashScope will not guess a specification from a marketing name."
    }

    private var missingEvidenceReasons: [String] {
        var reasons: [String] = []
        if specification == nil {
            reasons.append(connection.declaredSpecification.explanation ?? drive.capabilities.declaredUSBSpecification.explanation ?? "USB specification was not exposed")
        }
        if connection.negotiatedSpeed.value == nil, let reason = connection.negotiatedSpeed.explanation {
            reasons.append(reason)
        }
        if connection.vendorID.value == nil, let reason = connection.vendorID.explanation {
            reasons.append(reason)
        }
        if connection.productID.value == nil, let reason = connection.productID.explanation {
            reasons.append(reason)
        }
        if connection.portPath.value == nil, let reason = connection.portPath.explanation {
            reasons.append(reason)
        }
        if connection.allocatedMilliAmps.value == nil, let reason = connection.allocatedMilliAmps.explanation {
            reasons.append(reason)
        }
        if connection.availableMilliAmps.value == nil, let reason = connection.availableMilliAmps.explanation {
            reasons.append(reason)
        }
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
            Button {
                refreshAction()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            if includeSystemInformation {
                Button {
                    openSystemInformation()
                } label: {
                    Label("System Information", systemImage: "info.circle")
                }
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
