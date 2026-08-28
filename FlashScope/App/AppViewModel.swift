import AppKit
import FlashScopeCore
import Foundation
import Observation
import OSLog

struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var isCritical: Bool = false
}

@MainActor
@Observable
final class AppViewModel {
    let services: AppServices
    let preferences: AppPreferences

    var drives: [PhysicalDrive] = []
    var selectedDriveID: String?
    var selectedVolume: Volume?
    var connection = USBConnection()
    var healthSignals: [HealthSignal] = []
    var filesystemCheck = FilesystemCheckResult(status: .notRun, summary: "Not run")
    var benchmarkResult: BenchmarkResult?
    var diagnosis: DiagnosisReport?
    var history: [TestSession] = []
    var benchmarkProgress: BenchmarkProgress?
    var isRefreshing = false
    var isBenchmarking = false
    var isVerifyingFilesystem = false
    var notice: AppNotice?
    var cleanupNotices: [CleanupRecoveryNotice] = []

    @ObservationIgnored private var started = false
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var benchmarkTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private let logger = Logger(subsystem: "com.example.FlashScope", category: "app-state")

    init(services: AppServices, preferences: AppPreferences) {
        self.services = services
        self.preferences = preferences
    }

    var selectedDrive: PhysicalDrive? { drives.first(where: { $0.id == selectedDriveID }) }
    var simulationMode: Bool { services.simulationMode }

    func start() async {
        guard !started else { return }
        started = true
        await refresh()
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            for await updated in services.discovery.events() {
                await applyDiscoveryUpdate(updated)
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSystemSleep() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let updated = try await services.discovery.connectedDrives()
            await applyDiscoveryUpdate(updated)
        } catch {
            notice = .init(title: "Couldn’t refresh drives", message: "FlashScope could not refresh removable USB storage. \(error.localizedDescription)")
        }
    }

    func selectDrive(_ drive: PhysicalDrive) async {
        if selectedDriveID == drive.id, selectedVolume != nil { return }
        if isBenchmarking { cancelBenchmark(reason: "The selected drive changed during the test.") }
        selectedDriveID = drive.id
        selectedVolume = nil
        benchmarkResult = nil
        benchmarkProgress = nil
        filesystemCheck = .init(status: .notRun, summary: "Not run")
        diagnosis = nil
        history = []
        await inspect(drive)
    }

    func suggestedBenchmarkConfiguration() -> BenchmarkConfiguration? {
        guard let volume = selectedVolume, let drive = selectedDrive, drive.isRemovable, drive.isExternal, !drive.isInternal, !volume.isReadOnly else { return nil }
        let maximum = maximumSafeBenchmarkBytes(for: volume)
        guard maximum >= 32 * 1_024 * 1_024 else { return nil }
        var preset = preferences.defaultPreset
        if preset == .custom { preset = .standard }
        if preset == .extended, volume.filesystem.value == .fat32 { preset = .standard }
        var bytes = preset.defaultBytes
        if bytes > maximum {
            preset = .quick
            bytes = min(BenchmarkPreset.quick.defaultBytes, maximum)
        }
        return BenchmarkConfiguration(
            preset: preset,
            sizeBytes: bytes,
            sampleIntervalSeconds: preferences.sampleInterval,
            dataPattern: .deterministicPseudoRandom,
            includeSmallFileWorkload: preferences.includeSmallFileTest
        )
    }

    func maximumSafeBenchmarkBytes(for volume: Volume) -> UInt64 {
        let fractionLimit = UInt64(Double(volume.availableBytes) * FileBenchmarkService.maximumFreeSpaceFraction)
        let reserveLimit = volume.availableBytes > FileBenchmarkService.reserveBytes ? volume.availableBytes - FileBenchmarkService.reserveBytes : 0
        return min(fractionLimit, reserveLimit)
    }

    func startHealthCheck(configuration: BenchmarkConfiguration) {
        guard !isBenchmarking, let drive = selectedDrive, let volume = selectedVolume else { return }
        isBenchmarking = true
        benchmarkProgress = .init(phase: .preparing, completedBytes: 0, totalBytes: configuration.sizeBytes, message: "Confirming the selected removable target")
        let targetID = drive.id
        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await services.benchmark.run(
                    target: .init(drive: drive, volume: volume),
                    configuration: configuration,
                    progress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self, self.selectedDriveID == targetID else { return }
                            self.benchmarkProgress = progress
                        }
                    }
                )
                guard !Task.isCancelled, selectedDriveID == targetID else { return }
                benchmarkResult = result
                isBenchmarking = false
                benchmarkProgress = nil
                recomputeDiagnosis()
                try await persistCurrentSession()
                if result.integrity.status == .mismatch {
                    notice = .init(
                        title: "Integrity mismatch — back up now",
                        message: "Data read back from the benchmark did not match what FlashScope wrote. Back up important files immediately and stop relying on this drive until the cause is understood.",
                        isCritical: true
                    )
                }
            } catch is CancellationError {
                isBenchmarking = false
                benchmarkProgress = nil
                notice = .init(title: "Test cancelled", message: "The benchmark was cancelled. FlashScope attempted exact cleanup of its application-owned temporary data.")
            } catch {
                isBenchmarking = false
                benchmarkProgress = nil
                let urgent = Self.isUrgentIOError(error)
                notice = .init(
                    title: urgent ? "Storage error — back up important data" : "Health check stopped",
                    message: urgent
                        ? "The benchmark encountered an I/O, integrity, or cleanup error. Back up important data immediately. \(error.localizedDescription)"
                        : error.localizedDescription,
                    isCritical: urgent
                )
            }
        }
    }

    func cancelBenchmark(reason: String? = nil) {
        guard isBenchmarking else { return }
        benchmarkTask?.cancel()
        if let reason { notice = .init(title: "Benchmark interrupted", message: reason) }
    }

    func verifyFilesystemAfterConfirmation() async {
        guard let volume = selectedVolume, !isVerifyingFilesystem else { return }
        isVerifyingFilesystem = true
        defer { isVerifyingFilesystem = false }
        filesystemCheck = await services.filesystemVerification.verify(volume: volume, allowNormalUnmount: true)
        recomputeDiagnosis()
        do { try await persistCurrentSession() }
        catch { logger.error("History save failed after verification: \(error.localizedDescription, privacy: .private(mask: .hash))") }
        if filesystemCheck.status == .issuesDetected {
            notice = .init(title: "Filesystem issues reported", message: "Read-only verification reported problems. Back up important data before considering repair with a separate appropriate tool. FlashScope did not repair anything.", isCritical: true)
        } else if filesystemCheck.status == .unableToRun {
            notice = .init(title: "Verification could not run", message: filesystemCheck.summary)
        }
    }

    func safeEjectSelectedDrive() async {
        guard let drive = selectedDrive, !isBenchmarking else { return }
        let result = await services.eject.eject(drive)
        if !result.succeeded { notice = .init(title: "Couldn’t eject safely", message: result.message) }
    }

    func deleteHistory(_ session: TestSession) async {
        do {
            try await services.history.delete(session.id)
            await reloadHistory()
        } catch {
            notice = .init(title: "Couldn’t delete history", message: error.localizedDescription)
        }
    }

    func deleteAllHistory() async {
        do {
            try await services.history.deleteAll()
            history = []
        } catch { notice = .init(title: "Couldn’t delete history", message: error.localizedDescription) }
    }

    func currentSession() -> TestSession? {
        guard let drive = selectedDrive, let volume = selectedVolume, let diagnosis else { return nil }
        return TestSession(
            driveIdentityHash: PrivacyPreservingDriveIdentity.hash(drive: drive),
            drive: drive,
            volume: volume,
            connection: connection,
            benchmark: benchmarkResult,
            filesystemCheck: filesystemCheck,
            healthSignals: healthSignals,
            diagnosis: diagnosis
        )
    }

    private func applyDiscoveryUpdate(_ updated: [PhysicalDrive]) async {
        let previousSelected = selectedDriveID
        drives = updated.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        if let previousSelected, !updated.contains(where: { $0.id == previousSelected }) {
            if isBenchmarking {
                benchmarkTask?.cancel()
                isBenchmarking = false
                benchmarkProgress = nil
                notice = .init(
                    title: "Drive removed during test",
                    message: "The selected drive disappeared. FlashScope stopped the benchmark. If its temporary workspace could not be removed while disconnected, reconnect the same drive and automatic cleanup will only remove it after validating the ownership marker.",
                    isCritical: true
                )
            }
            selectedDriveID = nil
            selectedVolume = nil
            diagnosis = nil
            benchmarkResult = nil
        }
        if selectedDriveID == nil, let first = drives.first {
            await selectDrive(first)
        }
    }

    private func inspect(_ drive: PhysicalDrive) async {
        do {
            async let foundVolumes = services.volumes.volumes(for: drive)
            async let foundConnection = services.usb.connection(for: drive)
            async let foundSignals = services.health.signals(for: drive)
            let (volumes, usb, signals) = try await (foundVolumes, foundConnection, foundSignals)
            guard selectedDriveID == drive.id else { return }
            selectedVolume = volumes.first
            connection = usb
            healthSignals = signals
            await reloadHistory()
            recomputeDiagnosis()
            if preferences.automaticCleanupChecks, !simulationMode, let volume = selectedVolume {
                cleanupNotices = await services.cleanup.scanAndClean(mountRoot: URL(fileURLWithPath: volume.mountPath, isDirectory: true))
                if let refused = cleanupNotices.first(where: { !$0.cleaned }) {
                    notice = .init(title: "Temporary data needs attention", message: refused.message)
                }
            }
        } catch {
            notice = .init(title: "Couldn’t inspect drive", message: error.localizedDescription)
        }
    }

    private func reloadHistory() async {
        guard let drive = selectedDrive else { history = []; return }
        do {
            let identity = PrivacyPreservingDriveIdentity.hash(drive: drive)
            history = try await services.history.sessions(for: identity)
        } catch {
            history = []
            logger.error("History load failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    private func recomputeDiagnosis() {
        guard let drive = selectedDrive, let volume = selectedVolume else { diagnosis = nil; return }
        diagnosis = services.diagnosis.diagnose(.init(
            drive: drive,
            volume: volume,
            connection: connection,
            benchmark: benchmarkResult,
            filesystemCheck: filesystemCheck,
            healthSignals: healthSignals,
            historicalBenchmarks: history.compactMap(\.benchmark)
        ))
    }

    private func persistCurrentSession() async throws {
        guard let session = currentSession() else { return }
        try await services.history.save(session)
        if preferences.historyRetention != .forever {
            let cutoff = Calendar.current.date(byAdding: .day, value: -preferences.historyRetention.rawValue, to: Date()) ?? .distantPast
            try services.history.prune(olderThan: cutoff)
        }
        await reloadHistory()
    }

    private func handleSystemSleep() {
        guard isBenchmarking else { return }
        benchmarkTask?.cancel()
        notice = .init(
            title: "Benchmark stopped for system sleep",
            message: "FlashScope cancelled the active benchmark before sleep could make timing results misleading. Application-owned temporary data will be cleaned up through the normal verified cleanup path."
        )
    }

    private static func isUrgentIOError(_ error: Error) -> Bool {
        guard let benchmarkError = error as? BenchmarkError else { return false }
        switch benchmarkError {
        case .writeFailed, .readFailed, .flushFailed, .integrityMismatch, .cleanupFailed:
            return true
        default:
            return false
        }
    }

}

