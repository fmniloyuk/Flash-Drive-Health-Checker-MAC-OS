import Foundation
import DiskArbitration
import FlashScopeCore

struct MountOperationResult: Sendable {
    var succeeded: Bool
    var status: Int32?
    var message: String
}

protocol MountControlling: Sendable {
    func normalUnmount(_ volume: Volume) async -> MountOperationResult
    func mount(_ volume: Volume) async -> MountOperationResult
    func safeEject(_ drive: PhysicalDrive) async -> MountOperationResult
}

final class DiskArbitrationMountController: MountControlling, @unchecked Sendable {
    private let session: DASession?

    init() {
        session = DASessionCreate(kCFAllocatorDefault)
        if let session { DASessionSetDispatchQueue(session, DispatchQueue(label: "com.example.FlashScope.disk-arbitration")) }
    }

    func normalUnmount(_ volume: Volume) async -> MountOperationResult {
        guard let disk = disk(for: volume.bsdName) else { return .init(succeeded: false, status: nil, message: "Disk Arbitration could not resolve the selected volume") }
        return await withCheckedContinuation { continuation in
            let box = MountCallbackBox(continuation)
            DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), flashScopeUnmountCallback, Unmanaged.passRetained(box).toOpaque())
        }
    }

    func mount(_ volume: Volume) async -> MountOperationResult {
        guard let disk = disk(for: volume.bsdName) else { return .init(succeeded: false, status: nil, message: "Disk Arbitration could not resolve the selected volume") }
        return await withCheckedContinuation { continuation in
            let box = MountCallbackBox(continuation)
            DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionDefault), flashScopeMountCallback, Unmanaged.passRetained(box).toOpaque())
        }
    }

    func safeEject(_ drive: PhysicalDrive) async -> MountOperationResult {
        guard let disk = disk(for: drive.bsdName) else { return .init(succeeded: false, status: nil, message: "Disk Arbitration could not resolve the selected drive") }
        return await withCheckedContinuation { continuation in
            let box = MountCallbackBox(continuation)
            DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), flashScopeEjectCallback, Unmanaged.passRetained(box).toOpaque())
        }
    }

    private func disk(for bsdName: String) -> DADisk? {
        guard let session, RestrictedProcessRunner.isValidBSDName(bsdName) else { return nil }
        return "/dev/\(bsdName)".withCString { DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0) }
    }
}

private final class MountCallbackBox {
    let continuation: CheckedContinuation<MountOperationResult, Never>
    init(_ continuation: CheckedContinuation<MountOperationResult, Never>) { self.continuation = continuation }
}

private func result(from dissenter: DADissenter?) -> MountOperationResult {
    guard let dissenter else { return .init(succeeded: true, status: 0, message: "Completed") }
    let status = DADissenterGetStatus(dissenter)
    let text = DADissenterGetStatusString(dissenter).map { $0 as String } ?? "The volume is busy or the operation was refused"
    return .init(succeeded: false, status: status, message: text)
}

private func flashScopeUnmountCallback(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MountCallbackBox>.fromOpaque(context).takeRetainedValue().continuation.resume(returning: result(from: dissenter))
}

private func flashScopeMountCallback(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MountCallbackBox>.fromOpaque(context).takeRetainedValue().continuation.resume(returning: result(from: dissenter))
}

private func flashScopeEjectCallback(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MountCallbackBox>.fromOpaque(context).takeRetainedValue().continuation.resume(returning: result(from: dissenter))
}
