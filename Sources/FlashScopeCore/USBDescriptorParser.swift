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

    public static func negotiatedSpeed(fromDescriptor raw: String?) -> EvidenceAvailability<USBLinkSpeed> {
        guard let raw, !raw.isEmpty else { return .unavailable("Negotiated speed not exposed") }
        let normalized = raw.lowercased()
        if normalized.contains("super") && normalized.contains("plus") { return .available(.init(megabitsPerSecond: 10_000, label: "10 Gb/s")) }
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
}

public enum DriveVolumeMapper {
    public static func volumes(for driveID: String, from volumes: [Volume]) -> [Volume] {
        volumes.filter { $0.physicalDriveID == driveID }
    }
}
