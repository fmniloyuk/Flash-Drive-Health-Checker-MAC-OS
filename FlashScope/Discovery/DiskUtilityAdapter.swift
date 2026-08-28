import Foundation
import FlashScopeCore

struct DiskUtilityDriveRecord: Sendable {
    let drive: PhysicalDrive
    let volumeBSDNames: [String]
    let partitionScheme: EvidenceAvailability<PartitionScheme>
}

/// Typed, concurrency-safe subset of `diskutil info -plist` used by FlashScope.
///
/// `PropertyListSerialization` yields `[String: Any]`, which is intentionally kept
/// inside `DiskUtilityAdapter`'s actor isolation. Only this Sendable value crosses
/// the actor boundary under Swift 6 strict concurrency.
struct DiskUtilityInfo: Sendable {
    let internalDisk: Bool?
    let removableMedia: Bool?
    let ejectable: Bool?
    let busProtocol: String?
    let diskSize: UInt64?
    let mediaName: String?
    let deviceModel: String?
    let deviceVendor: String?
    let serialNumber: String?
    let smartStatus: String?
    let mountPoint: String?
    let volumeFreeSpace: UInt64?
    let readOnlyVolume: Bool?
    let volumeName: String?
    let filesystemType: String?
    let filesystemName: String?

    fileprivate init(plist: [String: Any]) {
        internalDisk = DiskUtilityAdapter.bool(plist["Internal"])
        removableMedia = DiskUtilityAdapter.bool(plist["RemovableMedia"])
        ejectable = DiskUtilityAdapter.bool(plist["Ejectable"])
        busProtocol = plist["BusProtocol"] as? String
        diskSize = DiskUtilityAdapter.uint64(plist["DiskSize"])
        mediaName = plist["MediaName"] as? String
        deviceModel = plist["DeviceModel"] as? String
        deviceVendor = plist["DeviceVendor"] as? String
        serialNumber = plist["SerialNumber"] as? String
        smartStatus = plist["SMARTStatus"] as? String
        mountPoint = plist["MountPoint"] as? String
        volumeFreeSpace = DiskUtilityAdapter.uint64(plist["VolumeFreeSpace"])
        readOnlyVolume = DiskUtilityAdapter.bool(plist["ReadOnlyVolume"])
        volumeName = plist["VolumeName"] as? String
        filesystemType = plist["FilesystemType"] as? String
        filesystemName = plist["FilesystemName"] as? String
    }
}

actor DiskUtilityAdapter {
    private let runner: any DiskUtilityRunning

    init(runner: any DiskUtilityRunning = RestrictedProcessRunner()) {
        self.runner = runner
    }

    func externalUSBDrives() async throws -> [DiskUtilityDriveRecord] {
        let result = try await runner.run(.listExternalPhysical)
        guard result.status == 0 else { return [] }
        let plist = try PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil)
        guard let root = plist as? [String: Any], let entries = root["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }

        var records: [DiskUtilityDriveRecord] = []
        for entry in entries {
            guard let bsdName = entry["DeviceIdentifier"] as? String, RestrictedProcessRunner.isValidBSDName(bsdName) else { continue }
            let info = try await info(for: bsdName)
            let internalDisk = info.internalDisk ?? true
            let removable = info.removableMedia ?? false
            let ejectable = info.ejectable ?? false
            let bus = info.busProtocol ?? ""
            guard !internalDisk, bus.caseInsensitiveCompare("USB") == .orderedSame, removable || ejectable else { continue }
            let capacity = info.diskSize ?? Self.uint64(entry["Size"]) ?? 0
            let displayName = info.mediaName ?? info.deviceModel ?? "USB Storage"
            let manufacturer = Self.availability(info.deviceVendor, unavailable: "Manufacturer not exposed")
            let model = Self.availability(info.deviceModel ?? info.mediaName, unavailable: "Model not exposed")
            let serial = Self.availability(info.serialNumber, unavailable: "Serial number not exposed")
            let smart = Self.smartCapability(info.smartStatus)
            let declared: EvidenceAvailability<USBSpecification> = .unavailable("USB specification is collected from IORegistry when exposed")
            let drive = PhysicalDrive(
                id: bsdName,
                bsdName: bsdName,
                displayName: displayName,
                manufacturer: manufacturer,
                model: model,
                serialNumber: serial,
                capacityBytes: capacity,
                isRemovable: removable,
                isEjectable: ejectable,
                isInternal: internalDisk,
                isExternal: !internalDisk,
                capabilities: .init(declaredUSBSpecification: declared, supportsSMART: smart)
            )
            let partitions = (entry["Partitions"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
            records.append(.init(drive: drive, volumeBSDNames: partitions, partitionScheme: Self.partitionScheme(entry["Content"] as? String)))
        }
        return records
    }

    func info(for bsdName: String) async throws -> DiskUtilityInfo {
        let result = try await runner.run(.info(bsdName))
        guard result.status == 0 else { return DiskUtilityInfo(plist: [:]) }
        let plist = try PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil)
        return DiskUtilityInfo(plist: plist as? [String: Any] ?? [:])
    }

    static func filesystem(from info: DiskUtilityInfo) -> EvidenceAvailability<FilesystemType> {
        let type = (info.filesystemType ?? "").lowercased()
        let name = (info.filesystemName ?? "").lowercased()
        let combined = type + " " + name
        if combined.contains("fat32") || combined.contains("ms-dos fat32") { return .available(.fat32) }
        if combined.contains("exfat") { return .available(.exfat) }
        if combined.contains("apfs") { return .available(.apfs) }
        if combined.contains("hfs") || combined.contains("journaled") { return .available(.hfsPlus) }
        if combined.contains("ntfs") { return .available(.ntfs) }
        if !combined.trimmingCharacters(in: .whitespaces).isEmpty { return .available(.other) }
        return .unavailable("Filesystem type not exposed")
    }

    static func partitionScheme(_ content: String?) -> EvidenceAvailability<PartitionScheme> {
        guard let content else { return .unavailable("Partition scheme unavailable") }
        if content.contains("GUID") { return .available(.guid) }
        if content.contains("FDisk") || content.contains("MBR") { return .available(.masterBootRecord) }
        if content.contains("Apple_partition") { return .available(.applePartitionMap) }
        return .available(.unknown)
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    static func uint64(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber { return value.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        return nil
    }

    static func availability(_ value: String?, unavailable: String) -> EvidenceAvailability<String> {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unavailable(unavailable) }
        return .available(value)
    }

    static func smartCapability(_ status: String?) -> EvidenceAvailability<Bool> {
        guard let status, !status.isEmpty else { return .unsupported("Not supported or not exposed") }
        if status.localizedCaseInsensitiveContains("not supported") { return .unsupported("Not supported or not exposed") }
        return .available(true)
    }
}
