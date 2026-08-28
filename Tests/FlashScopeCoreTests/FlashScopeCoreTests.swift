import XCTest
@testable import FlashScopeCore

final class FlashScopeCoreTests: XCTestCase {
    func testSHA256KnownVector() {
        XCTAssertEqual(SHA256Digest.hexDigest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testUnitCalculationsDistinguishMBAndMiB() {
        XCTAssertEqual(StorageFormatting.decimalMBPerSecond(bytes: 1_000_000, seconds: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(StorageFormatting.binaryMiBPerSecond(bytes: 1_048_576, seconds: 1), 1, accuracy: 0.0001)
        XCTAssertLessThan(StorageFormatting.throughput(100, unit: .mebibytesPerSecond), 100)
    }

    func testStatistics() {
        let stats = StatisticsCalculator.calculate(samples: [10, 20, 30, 40, 50])
        XCTAssertEqual(stats.minimum, 10)
        XCTAssertEqual(stats.maximum, 50)
        XCTAssertEqual(stats.average, 30)
        XCTAssertEqual(stats.median, 30)
        XCTAssertEqual(stats.p95, 50)
    }

    func testHealthyUSB2IsConnectionLimitedNotFailed() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.healthyUSB2())
        XCTAssertEqual(report.assessment.classification, .limitedByConnection)
        XCTAssertTrue(report.findings.contains { $0.title.contains("USB 2.0") })
        XCTAssertFalse(report.findings.contains { $0.severity == .critical })
        XCTAssertLessThan(report.assessment.confidence, 1.0, "Unavailable SMART should reduce confidence")
    }

    func testUSB3DeviceNegotiatedAtUSB2IsDetected() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.usb3NegotiatedAtUSB2())
        XCTAssertTrue(report.findings.contains { $0.title == "The device is connected at a reduced link speed" })
    }

    func testFastLinkPoorWrite() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.fastLinkPoorWrite())
        XCTAssertTrue(report.findings.contains { $0.category == .slowSequentialWrite })
    }

    func testSmallFileOverhead() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.smallFileOverhead())
        XCTAssertTrue(report.findings.contains { $0.category == .smallFileOverhead })
    }

    func testIntegrityMismatchIsCritical() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.integrityMismatch())
        XCTAssertEqual(report.assessment.classification, .critical)
        XCTAssertTrue(report.findings.contains { $0.category == .integrityFailure && $0.severity == .critical })
    }

    func testRepeatedIOErrorsAreCritical() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.repeatedIOErrors())
        XCTAssertEqual(report.assessment.classification, .critical)
    }

    func testVerificationBlockedIsNotCorruption() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.verificationBlocked())
        XCTAssertFalse(report.findings.contains { $0.severity >= .high && $0.category == .filesystemVerification })
        XCTAssertTrue(report.limitations.contains { $0.contains("did not run") })
    }

    func testNearlyFullFinding() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.nearlyFull())
        XCTAssertTrue(report.findings.contains { $0.category == .nearlyFull })
    }

    func testReadOnlyFinding() {
        let report = RuleBasedDiagnosisEngine().diagnose(DiagnosticFixtures.readOnly())
        XCTAssertTrue(report.findings.contains { $0.category == .readOnly })
    }

    func testUnsupportedSMARTDoesNotPenalizeMediaScore() {
        let input = DiagnosticFixtures.healthyUSB2()
        let report = RuleBasedDiagnosisEngine().diagnose(input)
        XCTAssertEqual(report.assessment.media.score, 92)
        XCTAssertTrue(report.findings.contains { $0.category == .unavailableHealthEvidence })
    }

    func testMissingNegotiatedSpeedReducesConfidence() {
        var input = DiagnosticFixtures.healthyUSB2()
        input.connection.negotiatedSpeed = .unavailable("Not exposed")
        let report = RuleBasedDiagnosisEngine().diagnose(input)
        XCTAssertLessThan(report.assessment.confidence, 0.8)
    }

    func testReportRedactsSerialAndUsername() throws {
        var input = DiagnosticFixtures.healthyUSB2()
        input.drive.serialNumber = .available("SECRET-123")
        input.volume.mountPath = "/Users/alice/Volumes/Test"
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
        let data = try DefaultReportGenerator().jsonReport(for: session, options: .init())
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(string.contains("SECRET-123"))
        XCTAssertFalse(string.contains("alice"))
        XCTAssertTrue(string.contains("redacted"))
        XCTAssertTrue(string.contains(JSONReportEnvelope.currentSchemaVersion))
    }

    func testDriveIdentityDoesNotContainSerial() {
        var drive = DiagnosticFixtures.healthyUSB2().drive
        drive.serialNumber = .available("TOP-SECRET")
        let identity = PrivacyPreservingDriveIdentity.hash(drive: drive)
        XCTAssertEqual(identity.count, 64)
        XCTAssertFalse(identity.contains("TOP-SECRET"))
    }

    func testSafeTemporaryPathRejectsSiblingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sibling = root.deletingLastPathComponent().appendingPathComponent(SafeTemporaryPath.directoryPrefix + UUID().uuidString)
        XCTAssertThrowsError(try SafeTemporaryPath.validateOwnedDirectory(sibling, mountRoot: root)) { error in
            XCTAssertEqual(error as? SafePathError, .targetOutsideMount)
        }
    }

    func testSafeTemporaryPathRejectsSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let link = root.appendingPathComponent(SafeTemporaryPath.directoryPrefix + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertThrowsError(try SafeTemporaryPath.validateOwnedDirectory(link, mountRoot: root)) { error in
            XCTAssertEqual(error as? SafePathError, .symbolicLinkRejected)
        }
    }

    func testBenchmarkRejectsInternalDisk() async {
        var input = DiagnosticFixtures.healthyUSB2()
        input.drive.isInternal = true
        let service = FileBenchmarkService()
        do {
            _ = try await service.run(target: .init(drive: input.drive, volume: input.volume), configuration: .init(preset: .custom, sizeBytes: 1_024 * 1_024), progress: { _ in })
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? BenchmarkError, .internalDiskRejected)
        }
    }

    func testBenchmarkPipelineCreatesVerifiesAndExactlyCleansTemporaryData() async throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("FlashScope-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mount) }
        let sentinel = mount.appendingPathComponent("do-not-touch.txt")
        try Data("sentinel".utf8).write(to: sentinel)

        var input = DiagnosticFixtures.healthyUSB2()
        input.drive.capacityBytes = 1_000_000_000
        input.volume.mountPath = mount.path
        input.volume.capacityBytes = 1_000_000_000
        input.volume.availableBytes = 800_000_000
        let config = BenchmarkConfiguration(preset: .custom, sizeBytes: 8 * 1_024 * 1_024, sampleIntervalSeconds: 0.1)
        let result = try await FileBenchmarkService().run(target: .init(drive: input.drive, volume: input.volume), configuration: config, progress: { _ in })
        XCTAssertEqual(result.integrity.status, .passed)
        XCTAssertEqual(result.cleanupStatus, .verified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: mount.path)
        XCTAssertEqual(remaining, ["do-not-touch.txt"])
    }

    func testBenchmarkCancellationCleansOwnedData() async throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("FlashScope-Cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mount) }
        var input = DiagnosticFixtures.healthyUSB2()
        input.volume.mountPath = mount.path
        input.volume.capacityBytes = 2_000_000_000
        input.volume.availableBytes = 1_500_000_000
        let task = Task {
            try await FileBenchmarkService().run(target: .init(drive: input.drive, volume: input.volume), configuration: .init(preset: .custom, sizeBytes: 64 * 1_024 * 1_024, sampleIntervalSeconds: 0.1), progress: { _ in })
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || error is BenchmarkError) }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: mount.path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(SafeTemporaryPath.directoryPrefix) })
    }
    func testOrphanCleanupRequiresValidOwnershipMarkerAndPreservesUnexpectedContent() async throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("FlashScope-Orphan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mount) }
        let token = UUID().uuidString
        let directory = mount.appendingPathComponent(SafeTemporaryPath.directoryPrefix + token, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let marker = directory.appendingPathComponent(OrphanedBenchmarkCleanupService.markerFilename)
        try JSONEncoder().encode(BenchmarkOwnershipMarker(token: token)).write(to: marker)
        try Data("payload".utf8).write(to: directory.appendingPathComponent(SafeTemporaryPath.benchmarkFilename))
        let notices = await OrphanedBenchmarkCleanupService().scanAndClean(mountRoot: mount)
        XCTAssertTrue(notices.contains { $0.cleaned })
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        let unsafeToken = UUID().uuidString
        let unsafe = mount.appendingPathComponent(SafeTemporaryPath.directoryPrefix + unsafeToken, isDirectory: true)
        try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: false)
        try JSONEncoder().encode(BenchmarkOwnershipMarker(token: unsafeToken)).write(to: unsafe.appendingPathComponent(OrphanedBenchmarkCleanupService.markerFilename))
        try Data("do not delete".utf8).write(to: unsafe.appendingPathComponent("unexpected.txt"))
        let refused = await OrphanedBenchmarkCleanupService().scanAndClean(mountRoot: mount)
        XCTAssertTrue(refused.contains { !$0.cleaned && $0.path == unsafe.path })
        XCTAssertTrue(FileManager.default.fileExists(atPath: unsafe.appendingPathComponent("unexpected.txt").path))
    }

    func testUSBDescriptorParsingKeepsDeclaredAndNegotiatedConceptsSeparate() {
        XCTAssertEqual(USBDescriptorParser.specification(fromBCDUSB: 0x0200).value, .usb2)
        XCTAssertEqual(USBDescriptorParser.specification(fromBCDUSB: 0x0310).value, .usb3)
        XCTAssertEqual(USBDescriptorParser.negotiatedSpeed(fromDescriptor: "High Speed").value?.megabitsPerSecond, 480)
        XCTAssertEqual(USBDescriptorParser.negotiatedSpeed(fromDescriptor: "SuperSpeed").value?.megabitsPerSecond, 5_000)
        XCTAssertNil(USBDescriptorParser.negotiatedSpeed(fromDescriptor: "descriptor=3").value)
    }

    func testNegotiatedSpeedClassification() {
        XCTAssertEqual(USBLinkSpeed(megabitsPerSecond: 480).classLabel, "High Speed")
        XCTAssertEqual(USBLinkSpeed(megabitsPerSecond: 5_000).classLabel, "SuperSpeed 5 Gb/s")
        XCTAssertEqual(USBLinkSpeed(megabitsPerSecond: 10_000).classLabel, "SuperSpeed 10 Gb/s")
    }

    func testDeviceToVolumeMapping() {
        let base = DiagnosticFixtures.healthyUSB2().volume
        let other = Volume(id: "other", physicalDriveID: "other-drive", bsdName: "disk99s1", name: "Other", mountPath: "/Volumes/Other", capacityBytes: 1, availableBytes: 1, filesystem: .available(.exfat), isMounted: true, isReadOnly: false, isRemovable: true, isEjectable: true)
        XCTAssertEqual(DriveVolumeMapper.volumes(for: base.physicalDriveID, from: [base, other]).map(\.id), [base.id])
    }

    func testBenchmarkRejectsFAT32FileAtFourGigabytes() async {
        var input = DiagnosticFixtures.healthyUSB2()
        input.volume.availableBytes = 20_000_000_000
        let service = FileBenchmarkService()
        do {
            _ = try await service.run(
                target: .init(drive: input.drive, volume: input.volume),
                configuration: .init(preset: .custom, sizeBytes: 4_000_000_000),
                progress: { _ in }
            )
            XCTFail("Expected FAT32 file-size rejection")
        } catch {
            XCTAssertEqual(error as? BenchmarkError, .filesystemFileSizeLimit)
        }
    }

    func testInsufficientReportedUSBPowerProducesFinding() {
        var input = DiagnosticFixtures.healthyUSB2()
        input.connection.allocatedMilliAmps = .available(900)
        input.connection.availableMilliAmps = .available(500)
        let report = RuleBasedDiagnosisEngine().diagnose(input)
        XCTAssertTrue(report.findings.contains { $0.category == .insufficientPower })
        XCTAssertEqual(report.assessment.classification, .attentionRecommended)
    }

    func testReportIncludesApplicationAndReportVersions() throws {
        let input = DiagnosticFixtures.healthyUSB2()
        let session = TestSession(
            driveIdentityHash: PrivacyPreservingDriveIdentity.hash(drive: input.drive),
            drive: input.drive,
            volume: input.volume,
            connection: input.connection,
            benchmark: input.benchmark,
            filesystemCheck: input.filesystemCheck,
            healthSignals: input.healthSignals,
            diagnosis: RuleBasedDiagnosisEngine().diagnose(input)
        )
        let data = try DefaultReportGenerator(applicationVersion: "1.2.3").jsonReport(for: session, options: .init())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(JSONReportEnvelope.self, from: data)
        XCTAssertEqual(envelope.applicationVersion, "1.2.3")
        XCTAssertEqual(envelope.reportVersion, JSONReportEnvelope.currentSchemaVersion)
    }

}
