import Foundation
import FlashScopeCore

protocol SafeEjectService: Sendable {
    func eject(_ drive: PhysicalDrive) async -> MountOperationResult
}

struct LiveSafeEjectService: SafeEjectService {
    let controller: DiskArbitrationMountController
    func eject(_ drive: PhysicalDrive) async -> MountOperationResult { await controller.safeEject(drive) }
}

struct SimulationSafeEjectService: SafeEjectService {
    func eject(_ drive: PhysicalDrive) async -> MountOperationResult { .init(succeeded: true, status: 0, message: "Simulation: ejected") }
}

@MainActor
struct AppServices {
    let discovery: any DriveDiscoveryService
    let usb: any USBTopologyService
    let volumes: any VolumeInformationService
    let benchmark: any BenchmarkService
    let filesystemVerification: any FilesystemVerificationService
    let health: any HealthSignalService
    let diagnosis: any DiagnosisEngine
    let reports: any ReportGenerator
    let history: SwiftDataHistoryRepository
    let eject: any SafeEjectService
    let cleanup: OrphanedBenchmarkCleanupService
    let simulationMode: Bool

    static func make() -> AppServices {
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        let emptySimulation = args.contains("--simulate-empty")
        let simulation = args.contains("--simulate") || emptySimulation || ProcessInfo.processInfo.environment["FLASHSCOPE_SIMULATOR"] == "1"
        #else
        let emptySimulation = false
        let simulation = false
        #endif
        let inMemoryHistory = args.contains("--ui-testing")
        let history = try! SwiftDataHistoryRepository(inMemoryOnly: inMemoryHistory)
        if simulation {
            return .init(
                discovery: SimulationDriveDiscoveryService(empty: emptySimulation),
                usb: SimulationUSBTopologyService(),
                volumes: SimulationVolumeInformationService(),
                benchmark: SimulationBenchmarkService(),
                filesystemVerification: SimulationFilesystemVerificationService(),
                health: SimulationHealthSignalService(),
                diagnosis: RuleBasedDiagnosisEngine(),
                reports: DefaultReportGenerator(),
                history: history,
                eject: SimulationSafeEjectService(),
                cleanup: OrphanedBenchmarkCleanupService(),
                simulationMode: true
            )
        }
        let runner = RestrictedProcessRunner()
        let diskAdapter = DiskUtilityAdapter(runner: runner)
        let mount = DiskArbitrationMountController()
        return .init(
            discovery: DiskArbitrationDriveDiscoveryService(adapter: diskAdapter),
            usb: IOKitUSBTopologyService(),
            volumes: MacOSVolumeInformationService(adapter: diskAdapter),
            benchmark: FileBenchmarkService(),
            filesystemVerification: MacOSFilesystemVerificationService(runner: runner, mountController: mount),
            health: MacOSHealthSignalService(adapter: diskAdapter),
            diagnosis: RuleBasedDiagnosisEngine(),
            reports: DefaultReportGenerator(),
            history: history,
            eject: LiveSafeEjectService(controller: mount),
            cleanup: OrphanedBenchmarkCleanupService(),
            simulationMode: false
        )
    }
}
