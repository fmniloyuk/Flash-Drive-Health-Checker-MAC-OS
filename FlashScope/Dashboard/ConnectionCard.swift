import FlashScopeCore
import SwiftUI

struct ConnectionCard: View {
    let drive: PhysicalDrive
    let connection: USBConnection
    let diagnosis: DiagnosisReport?

    var body: some View {
        DiagnosticCard("Connection", systemImage: "cable.connector", subtitle: "Declared capability and negotiated link are kept separate") {
            VStack(spacing: 9) {
                MetricRow(label: "Device USB specification", value: connection.declaredSpecification.value?.rawValue ?? drive.capabilities.declaredUSBSpecification.value?.rawValue ?? "Unavailable")
                MetricRow(label: "Negotiated link", value: connection.negotiatedSpeed.value?.label ?? "Unavailable", detail: connection.negotiatedSpeed.value?.classLabel)
                MetricRow(label: "Theoretical bus ceiling", value: theoreticalCeiling)
                MetricRow(label: "Expected practical read range", value: expectedRange)
                MetricRow(label: "Connection path", value: connectionPath)
                MetricRow(label: "Vendor / Product ID", value: identifiers)
                MetricRow(label: "Power allocation", value: power)

                if isReducedUSB3Link {
                    InsetNotice(kind: .warning, title: "USB 3-capable device on a USB 2-class link", message: "Try a direct USB 3-capable port, remove hubs/adapters where practical, and reconnect the device. FlashScope does not infer this from a marketing name alone.")
                }
                if connection.negotiatedSpeed.value == nil {
                    InsetNotice(kind: .info, title: "Negotiated speed unavailable", message: "macOS did not expose a link speed that FlashScope could classify safely, so connection diagnosis confidence is reduced.")
                }
                if !connection.topology.isEmpty {
                    DisclosureGroup("USB topology") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(connection.topology) { node in
                                Label(node.name, systemImage: node.kind.localizedCaseInsensitiveContains("hub") ? "point.3.connected.trianglepath.dotted" : "circle.dotted")
                                    .font(.caption)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
        .accessibilityIdentifier("connection-card")
    }

    private var theoreticalCeiling: String {
        guard let speed = connection.negotiatedSpeed.value else { return "Unavailable" }
        return String(format: "%.1f MB/s bus maximum", speed.theoreticalMegabytesPerSecond)
    }
    private var expectedRange: String {
        guard let range = diagnosis?.expectedPracticalRangeMBps else { return "Unavailable" }
        return String(format: "%.0f–%.0f MB/s guidance", range.lowerBound, range.upperBound)
    }
    private var connectionPath: String {
        switch connection.hubOrAdapterDetected {
        case .available(true): "Hub or adapter detected"
        case .available(false): "No hub detected in exposed topology"
        default: "Unavailable"
        }
    }
    private var identifiers: String {
        let vendor = connection.vendorID.value.map { String(format: "0x%04X", $0) } ?? "—"
        let product = connection.productID.value.map { String(format: "0x%04X", $0) } ?? "—"
        return "\(vendor) / \(product)"
    }
    private var power: String {
        let allocated = connection.allocatedMilliAmps.value.map { "\($0) mA allocated" }
        let available = connection.availableMilliAmps.value.map { "\($0) mA available" }
        return [allocated, available].compactMap { $0 }.joined(separator: ", ").nilIfEmpty ?? "Unavailable"
    }
    private var isReducedUSB3Link: Bool {
        let spec = connection.declaredSpecification.value ?? drive.capabilities.declaredUSBSpecification.value
        guard spec == .usb3 || spec == .usb4, let speed = connection.negotiatedSpeed.value else { return false }
        return speed.megabitsPerSecond <= 500
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
