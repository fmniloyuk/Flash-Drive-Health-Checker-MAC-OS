import Foundation
import DiskArbitration
import FlashScopeCore
import OSLog

final class DiskArbitrationDriveDiscoveryService: DriveDiscoveryService, @unchecked Sendable {
    private let adapter: DiskUtilityAdapter
    private let logger = Logger(subsystem: "com.example.FlashScope", category: "discovery")
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<[PhysicalDrive]>.Continuation] = [:]
    private var session: DASession?
    private var monitoringStarted = false

    init(adapter: DiskUtilityAdapter = .init()) {
        self.adapter = adapter
    }

    func connectedDrives() async throws -> [PhysicalDrive] {
        let records = try await adapter.externalUSBDrives()
        logger.info("Discovered \(records.count, privacy: .public) removable external USB drives")
        return records.map(\.drive)
    }

    func events() -> AsyncStream<[PhysicalDrive]> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.removeContinuation(id) }
            startMonitoringIfNeeded()
        }
    }

    private func startMonitoringIfNeeded() {
        lock.lock()
        let shouldStart = !monitoringStarted
        if shouldStart { monitoringStarted = true }
        lock.unlock()
        guard shouldStart else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, let session = DASessionCreate(kCFAllocatorDefault) else { return }
            self.session = session
            let context = Unmanaged.passUnretained(self).toOpaque()
            DARegisterDiskAppearedCallback(session, nil, flashScopeDiskAppeared, context)
            DARegisterDiskDisappearedCallback(session, nil, flashScopeDiskDisappeared, context)
            DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
    }

    fileprivate func diskSetChanged() {
        Task {
            do { broadcast(try await connectedDrives()) }
            catch { logger.error("USB discovery refresh failed: \(error.localizedDescription, privacy: .private(mask: .hash))") }
        }
    }

    private func broadcast(_ drives: [PhysicalDrive]) {
        lock.lock()
        let values = Array(continuations.values)
        lock.unlock()
        for continuation in values { continuation.yield(drives) }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock(); continuations.removeValue(forKey: id); lock.unlock()
    }

    deinit {
        if let session {
            DispatchQueue.main.async {
                DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            }
        }
    }
}

private func flashScopeDiskAppeared(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<DiskArbitrationDriveDiscoveryService>.fromOpaque(context).takeUnretainedValue().diskSetChanged()
}

private func flashScopeDiskDisappeared(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<DiskArbitrationDriveDiscoveryService>.fromOpaque(context).takeUnretainedValue().diskSetChanged()
}
