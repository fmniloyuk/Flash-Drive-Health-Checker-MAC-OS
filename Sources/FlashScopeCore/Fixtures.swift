import Foundation

public enum DiagnosticFixtures {
    public static func healthyUSB2() -> DiagnosisInput {
        let drive = PhysicalDrive(
            id: "fixture-usb2",
            bsdName: "disk9",
            displayName: "31 GB USB Flash Drive",
            capacityBytes: 31_000_000_000,
            isRemovable: true,
            isEjectable: true,
            isInternal: false,
            isExternal: true,
            capabilities: .init(declaredUSBSpecification: .available(.usb2), supportsSMART: .unsupported("Not supported or not exposed"))
        )
        let volume = Volume(
            id: "fixture-usb2-volume",
            physicalDriveID: drive.id,
            bsdName: "disk9s1",
            name: "USB DRIVE",
            mountPath: "/Volumes/USB DRIVE",
            capacityBytes: 31_000_000_000,
            availableBytes: UInt64(Double(31_000_000_000) * 0.52),
            filesystem: .available(.fat32),
            partitionScheme: .available(.masterBootRecord),
            isMounted: true,
            isReadOnly: false,
            isRemovable: true,
            isEjectable: true
        )
        let connection = USBConnection(
            declaredSpecification: .available(.usb2),
            negotiatedSpeed: .available(.init(megabitsPerSecond: 480, label: "480 Mb/s")),
            vendorID: .available(0x1234),
            productID: .available(0x5678),
            hubOrAdapterDetected: .available(false)
        )
        let benchmark = makeBenchmark(read: 27.1, write: 18.4)
        return DiagnosisInput(
            drive: drive,
            volume: volume,
            connection: connection,
            benchmark: benchmark,
            filesystemCheck: .init(status: .passed, summary: "Filesystem verification completed without reported errors"),
            healthSignals: [.init(kind: .smart, availability: .unsupported("Not supported or not exposed"))]
        )
    }

    public static func usb3NegotiatedAtUSB2() -> DiagnosisInput {
        var input = healthyUSB2()
        input.drive.capabilities.declaredUSBSpecification = .available(.usb3)
        input.connection.declaredSpecification = .available(.usb3)
        return input
    }

    public static func fastLinkPoorWrite() -> DiagnosisInput {
        var input = healthyUSB2()
        input.drive.capabilities.declaredUSBSpecification = .available(.usb3)
        input.connection.declaredSpecification = .available(.usb3)
        input.connection.negotiatedSpeed = .available(.init(megabitsPerSecond: 5_000, label: "5 Gb/s"))
        input.benchmark = makeBenchmark(read: 180, write: 9.5)
        return input
    }

    public static func smallFileOverhead() -> DiagnosisInput {
        var input = fastLinkPoorWrite()
        var benchmark = makeBenchmark(read: 210, write: 135)
        benchmark.smallFileResult = .init(totalBytes: 8_000_000, fileCount: 48, megabytesPerSecond: 4.5, filesPerSecond: 82, operationsPerSecond: 328)
        input.benchmark = benchmark
        return input
    }

    public static func integrityMismatch() -> DiagnosisInput {
        var input = healthyUSB2()
        var benchmark = makeBenchmark(read: 24, write: 16)
        benchmark.integrity = .init(status: .mismatch, expectedDigest: "aa", actualDigest: "bb")
        input.benchmark = benchmark
        return input
    }

    public static func repeatedIOErrors() -> DiagnosisInput {
        var input = healthyUSB2()
        var benchmark = makeBenchmark(read: 8, write: 5)
        benchmark.ioErrorCount = 3
        input.benchmark = benchmark
        return input
    }

    public static func verificationBlocked() -> DiagnosisInput {
        var input = healthyUSB2()
        input.filesystemCheck = .init(status: .unableToRun, summary: "Volume could not be unmounted because another process is using it", exitStatus: 16, verificationTool: "diskutil", requiredUnmount: true)
        return input
    }

    public static func nearlyFull() -> DiagnosisInput {
        var input = healthyUSB2()
        input.volume.availableBytes = UInt64(Double(input.volume.capacityBytes) * 0.04)
        return input
    }

    public static func readOnly() -> DiagnosisInput {
        var input = healthyUSB2()
        input.volume.isReadOnly = true
        input.benchmark = nil
        return input
    }

    public static func removedDuringBenchmark() -> DiagnosisInput {
        var input = healthyUSB2()
        input.benchmark = nil
        input.healthSignals.append(.init(kind: .ioErrors, availability: .failed("Drive was removed while the benchmark was active")))
        return input
    }

    public static func profiles() -> [(String, DiagnosisInput)] {
        [
            ("Healthy USB 2.0", healthyUSB2()),
            ("USB 3 → USB 2 link", usb3NegotiatedAtUSB2()),
            ("Fast link, slow writes", fastLinkPoorWrite()),
            ("Small-file overhead", smallFileOverhead()),
            ("Integrity mismatch", integrityMismatch()),
            ("Repeated I/O errors", repeatedIOErrors()),
            ("Verification blocked", verificationBlocked()),
            ("Nearly full", nearlyFull()),
            ("Read-only", readOnly()),
            ("Drive removed", removedDuringBenchmark())
        ]
    }

    public static func makeBenchmark(read: Double, write: Double) -> BenchmarkResult {
        let writeSamples = [write * 0.95, write, write * 1.04].enumerated().map { index, value in
            ThroughputSample(elapsedSeconds: Double(index + 1), megabytesPerSecond: value, phase: .writing)
        }
        let readSamples = [read * 0.96, read, read * 1.03].enumerated().map { index, value in
            ThroughputSample(elapsedSeconds: Double(index + 1), megabytesPerSecond: value, phase: .reading)
        }
        return BenchmarkResult(
            configuration: .init(),
            writeMegabytesPerSecond: write,
            readMegabytesPerSecond: read,
            writeDurationSeconds: 55,
            readDurationSeconds: 38,
            writeSamples: writeSamples,
            readSamples: readSamples,
            writeStatistics: StatisticsCalculator.calculate(samples: writeSamples.map(\.megabytesPerSecond)),
            readStatistics: StatisticsCalculator.calculate(samples: readSamples.map(\.megabytesPerSecond)),
            integrity: .init(status: .passed, expectedDigest: "fixture", actualDigest: "fixture")
        )
    }
}
