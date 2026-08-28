import Foundation

public enum USBDescriptorParser {
    public static func specification(fromBCDUSB value: UInt64?) -> EvidenceAvailability<USBSpecification> {
        guard let value else { return .unavailable("USB specification descriptor unavailable") }
        switch value {
        case 0x0000..<0x0200: return .available(.usb1)
        case 0x0200..<0x0300: return .available(.usb2)
        case 0x0300..<0x0400: return .available(.usb3)
        default: return .available(.usb4)
        }
    }

    /// Parses the textual forms commonly exposed by IORegistry and system tools.
    /// Declared USB capability and the currently negotiated link remain separate concepts.
    public static func negotiatedSpeed(fromDescriptor raw: String?) -> EvidenceAvailability<USBLinkSpeed> {
        guard let raw, !raw.isEmpty else { return .unavailable("Negotiated speed not exposed") }
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Some IORegistry implementations expose the Apple connection-speed enum as a string.
        if let numeric = UInt64(normalized) {
            return negotiatedSpeed(fromNumericDescriptor: numeric)
        }

        if normalized.contains("super") && normalized.contains("plus") && normalized.contains("by2") {
            return .available(.init(megabitsPerSecond: 20_000, label: "20 Gb/s"))
        }
        if normalized.contains("super") && normalized.contains("plus") {
            return .available(.init(megabitsPerSecond: 10_000, label: "10 Gb/s"))
        }
        if normalized.contains("super") { return .available(.init(megabitsPerSecond: 5_000, label: "5 Gb/s")) }
        if normalized.contains("high") { return .available(.init(megabitsPerSecond: 480, label: "480 Mb/s")) }
        if normalized.contains("full") { return .available(.init(megabitsPerSecond: 12, label: "12 Mb/s")) }
        if normalized.contains("low") { return .available(.init(megabitsPerSecond: 1.5, label: "1.5 Mb/s")) }

        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if let range = compact.range(of: #"[0-9]+(?:\.[0-9]+)?gb/s"#, options: .regularExpression) {
            let number = compact[range].replacingOccurrences(of: "gb/s", with: "")
            if let value = Double(number) { return .available(.init(megabitsPerSecond: value * 1_000, label: "\(value.formatted()) Gb/s")) }
        }
        if let range = compact.range(of: #"[0-9]+(?:\.[0-9]+)?mb/s"#, options: .regularExpression) {
            let number = compact[range].replacingOccurrences(of: "mb/s", with: "")
            if let value = Double(number) { return .available(.init(megabitsPerSecond: value, label: "\(value.formatted()) Mb/s")) }
        }
        return .unavailable("Speed descriptor was exposed but could not be classified safely")
    }

    /// Parses Apple's `tIOUSBHostConnectionSpeed` values exposed by the `USBSpeed`
    /// IORegistry property. These values follow the XHCI speed ID mapping used by
    /// IOUSBHostFamily: 1=Full, 2=Low, 3=High, 4=Super, 5=SuperPlus, 6=SuperPlusBy2.
    ///
    /// A few older bridges/tools expose the literal Mbps value instead, so the
    /// well-known literal values are accepted as a conservative fallback.
    public static func negotiatedSpeed(fromNumericDescriptor value: UInt64?) -> EvidenceAvailability<USBLinkSpeed> {
        guard let value else { return .unavailable("Negotiated speed not exposed") }
        switch value {
        case 0:
            return .unavailable("USB speed property reports no active connection")
        case 1:
            return .available(.init(megabitsPerSecond: 12, label: "12 Mb/s"))
        case 2:
            return .available(.init(megabitsPerSecond: 1.5, label: "1.5 Mb/s"))
        case 3:
            return .available(.init(megabitsPerSecond: 480, label: "480 Mb/s"))
        case 4:
            return .available(.init(megabitsPerSecond: 5_000, label: "5 Gb/s"))
        case 5:
            return .available(.init(megabitsPerSecond: 10_000, label: "10 Gb/s"))
        case 6:
            return .available(.init(megabitsPerSecond: 20_000, label: "20 Gb/s"))
        case 12:
            return .available(.init(megabitsPerSecond: 12, label: "12 Mb/s"))
        case 480:
            return .available(.init(megabitsPerSecond: 480, label: "480 Mb/s"))
        case 5_000:
            return .available(.init(megabitsPerSecond: 5_000, label: "5 Gb/s"))
        case 10_000:
            return .available(.init(megabitsPerSecond: 10_000, label: "10 Gb/s"))
        case 20_000:
            return .available(.init(megabitsPerSecond: 20_000, label: "20 Gb/s"))
        default:
            return .unavailable("Numeric USB speed descriptor \(value) is not a recognized connection-speed value")
        }
    }
}

public enum DriveVolumeMapper {
    public static func volumes(for driveID: String, from volumes: [Volume]) -> [Volume] {
        volumes.filter { $0.physicalDriveID == driveID }
    }
}
