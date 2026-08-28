import XCTest
import FlashScopeCore
@testable import FlashScope

final class FlashScopeIntegrationTests: XCTestCase {
    func testSimulatorDiscoveryLifecyclePublishesFixtures() async throws {
        let service = SimulationDriveDiscoveryService()
        let drives = try await service.connectedDrives()
        XCTAssertEqual(drives.count, 10)
        var iterator = service.events().makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event?.count, 10)
    }

    func testVerificationUsesNormalUnmountAndNeverRepair() async {
        let runner = MockDiskUtilityRunner(result: .init(status: 0, stdout: Data(), stderr: Data()))
        let mount = MockMountController(unmount: .init(succeeded: true, status: 0, message: "ok"), mount: .init(succeeded: true, status: 0, message: "ok"))
        let service = MacOSFilesystemVerificationService(runner: runner, mountController: mount)
        let volume = DiagnosticFixtures.healthyUSB2().volume
        let result = await service.verify(volume: volume, allowNormalUnmount: true)
        XCTAssertEqual(result.status, .passed)
        let operations = await runner.operations
        let unmountCalls = await mount.normalUnmountCalls
        let mountCalls = await mount.mountCalls
        XCTAssertEqual(operations, [.verifyVolume(volume.bsdName)])
        XCTAssertEqual(unmountCalls, 1)
        XCTAssertEqual(mountCalls, 1)
    }

    func testVerificationBlockedByBusyVolumeIsInconclusive() async {
        let runner = MockDiskUtilityRunner(result: .init(status: 0, stdout: Data(), stderr: Data()))
        let mount = MockMountController(unmount: .init(succeeded: false, status: 16, message: "busy"), mount: .init(succeeded: true, status: 0, message: "ok"))
        let service = MacOSFilesystemVerificationService(runner: runner, mountController: mount)
        let result = await service.verify(volume: DiagnosticFixtures.healthyUSB2().volume, allowNormalUnmount: true)
        XCTAssertEqual(result.status, .unableToRun)
        let operations = await runner.operations
        XCTAssertTrue(operations.isEmpty)
    }

    @MainActor
    func testSwiftDataHistoryPersistenceInMemory() async throws {
        let repository = try SwiftDataHistoryRepository(inMemoryOnly: true)
        let input = DiagnosticFixtures.healthyUSB2()
        let diagnosis = RuleBasedDiagnosisEngine().diagnose(input)
        let session = TestSession(
            driveIdentityHash: PrivacyPreservingDriveIdentity.hash(drive: input.drive),
            drive: input.drive,
            volume: input.volume,
            connection: input.connection,
            benchmark: input.benchmark,
            filesystemCheck: input.filesystemCheck,
            healthSignals: input.healthSignals,
            diagnosis: diagnosis
        )
        try await repository.save(session)
        let sessionsAfterSave = try await repository.sessions(for: session.driveIdentityHash)
        XCTAssertEqual(sessionsAfterSave.count, 1)

        try await repository.delete(session.id)

        let sessionsAfterDelete = try await repository.sessions(for: session.driveIdentityHash)
        XCTAssertEqual(sessionsAfterDelete.count, 0)
    }
}

private actor MockDiskUtilityRunner: DiskUtilityRunning {
    let result: RestrictedCommandResult
    private(set) var operations: [DiskUtilityOperation] = []
    init(result: RestrictedCommandResult) { self.result = result }
    func run(_ operation: DiskUtilityOperation) async throws -> RestrictedCommandResult {
        operations.append(operation)
        return result
    }
}

private actor MockMountController: MountControlling {
    let unmountResult: MountOperationResult
    let mountResult: MountOperationResult
    private(set) var normalUnmountCalls = 0
    private(set) var mountCalls = 0
    init(unmount: MountOperationResult, mount: MountOperationResult) {
        self.unmountResult = unmount
        self.mountResult = mount
    }
    func normalUnmount(_ volume: Volume) async -> MountOperationResult { normalUnmountCalls += 1; return unmountResult }
    func mount(_ volume: Volume) async -> MountOperationResult { mountCalls += 1; return mountResult }
    func safeEject(_ drive: PhysicalDrive) async -> MountOperationResult { .init(succeeded: true, status: 0, message: "ok") }
}
