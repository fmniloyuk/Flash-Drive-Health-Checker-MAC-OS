import Foundation
import FlashScopeCore

struct MacOSVolumeInformationService: VolumeInformationService {
    let adapter: DiskUtilityAdapter

    init(adapter: DiskUtilityAdapter = .init()) {
        self.adapter = adapter
    }

    func volumes(for drive: PhysicalDrive) async throws -> [Volume] {
        guard let record = try await adapter.externalUSBDrives().first(where: { $0.drive.bsdName == drive.bsdName }) else { return [] }
        var result: [Volume] = []
        let candidates = record.volumeBSDNames.isEmpty ? [drive.bsdName] : record.volumeBSDNames
        for bsdName in candidates {
            let info = try await adapter.info(for: bsdName)
            guard let mountPath = info.mountPoint, !mountPath.isEmpty else { continue }
            let url = URL(fileURLWithPath: mountPath, isDirectory: true)
            let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsReadOnlyKey, .volumeIsRemovableKey])
            let capacity: UInt64
            if let resourceCapacity = values?.volumeTotalCapacity, resourceCapacity >= 0 {
                capacity = UInt64(resourceCapacity)
            } else {
                capacity = info.diskSize ?? 0
            }
            let available: UInt64
            if let resourceAvailable = values?.volumeAvailableCapacityForImportantUsage, resourceAvailable >= 0 {
                available = UInt64(resourceAvailable)
            } else {
                available = info.volumeFreeSpace ?? 0
            }
            let readOnly = values?.volumeIsReadOnly ?? info.readOnlyVolume ?? false
            let removable = values?.volumeIsRemovable ?? drive.isRemovable
            let name = values?.volumeName ?? info.volumeName ?? "Untitled"
            result.append(Volume(
                id: "\(drive.id)-\(bsdName)",
                physicalDriveID: drive.id,
                bsdName: bsdName,
                name: name,
                mountPath: mountPath,
                capacityBytes: capacity,
                availableBytes: available,
                filesystem: DiskUtilityAdapter.filesystem(from: info),
                partitionScheme: record.partitionScheme,
                isMounted: true,
                isReadOnly: readOnly,
                isRemovable: removable,
                isEjectable: drive.isEjectable
            ))
        }
        return result
    }
}
