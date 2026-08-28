import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum BenchmarkError: Error, LocalizedError, Equatable, Sendable {
    case internalDiskRejected
    case nonRemovableTargetRejected
    case unmountedVolume
    case readOnlyVolume
    case insufficientFreeSpace(required: UInt64, available: UInt64)
    case unsafeCustomSize
    case filesystemFileSizeLimit
    case pathAlreadyExists
    case alreadyRunning
    case createDirectoryFailed
    case createFileFailed
    case writeFailed(String)
    case flushFailed(String)
    case readFailed(String)
    case integrityMismatch
    case cleanupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .internalDiskRejected: "FlashScope never benchmarks the internal system disk."
        case .nonRemovableTargetRejected: "The selected target is not removable external storage."
        case .unmountedVolume: "The selected volume is not mounted."
        case .readOnlyVolume: "The selected volume is read-only; write testing was skipped."
        case let .insufficientFreeSpace(required, available): "Insufficient free space. Required \(StorageFormatting.bytes(required)); available \(StorageFormatting.bytes(available))."
        case .unsafeCustomSize: "The benchmark size exceeds the safe fraction of available space."
        case .filesystemFileSizeLimit: "The benchmark file would exceed the selected filesystem's single-file limit."
        case .pathAlreadyExists: "The unique benchmark path unexpectedly already exists."
        case .alreadyRunning: "A benchmark is already active for this physical drive."
        case .createDirectoryFailed: "The application-owned benchmark directory could not be created."
        case .createFileFailed: "The benchmark file could not be created without overwriting an existing path."
        case let .writeFailed(reason): "Benchmark write failed: \(reason)"
        case let .flushFailed(reason): "Durable flush failed: \(reason)"
        case let .readFailed(reason): "Benchmark read failed: \(reason)"
        case .integrityMismatch: "Benchmark data integrity verification failed. Back up this drive immediately."
        case let .cleanupFailed(reason): "Benchmark cleanup could not be verified: \(reason)"
        }
    }
}

public actor FileBenchmarkService: BenchmarkService {
    public static let maximumFreeSpaceFraction = 0.25
    public static let reserveBytes: UInt64 = 128 * 1_024 * 1_024
    private let chunkSize = 4 * 1_024 * 1_024
    private var activeDriveIDs: Set<String> = []

    public init() {}

    public func run(
        target: BenchmarkTarget,
        configuration: BenchmarkConfiguration,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        try preflight(target: target, configuration: configuration)
        guard !activeDriveIDs.contains(target.drive.id) else { throw BenchmarkError.alreadyRunning }
        activeDriveIDs.insert(target.drive.id)
        defer { activeDriveIDs.remove(target.drive.id) }
        return try await perform(target: target, configuration: configuration, progress: progress)
    }

    private func preflight(target: BenchmarkTarget, configuration: BenchmarkConfiguration) throws {
        guard !target.drive.isInternal else { throw BenchmarkError.internalDiskRejected }
        guard target.drive.isExternal, target.drive.isRemovable, target.volume.isRemovable else {
            throw BenchmarkError.nonRemovableTargetRejected
        }
        guard target.volume.isMounted else { throw BenchmarkError.unmountedVolume }
        guard !target.volume.isReadOnly else { throw BenchmarkError.readOnlyVolume }
        guard configuration.sizeBytes > 0 else { throw BenchmarkError.unsafeCustomSize }
        if target.volume.filesystem.value == .fat32, configuration.sizeBytes >= 4_000_000_000 {
            throw BenchmarkError.filesystemFileSizeLimit
        }
        let required = configuration.sizeBytes + Self.reserveBytes
        guard target.volume.availableBytes >= required else {
            throw BenchmarkError.insufficientFreeSpace(required: required, available: target.volume.availableBytes)
        }
        let maxSafe = UInt64(Double(target.volume.availableBytes) * Self.maximumFreeSpaceFraction)
        guard configuration.sizeBytes <= maxSafe else { throw BenchmarkError.unsafeCustomSize }
    }

    private func perform(
        target: BenchmarkTarget,
        configuration: BenchmarkConfiguration,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        let mountRoot = URL(fileURLWithPath: target.volume.mountPath, isDirectory: true)
        let token = UUID().uuidString
        let ownedDirectory = mountRoot.appendingPathComponent(SafeTemporaryPath.directoryPrefix + token, isDirectory: true)
        let fileURL = ownedDirectory.appendingPathComponent(SafeTemporaryPath.benchmarkFilename, isDirectory: false)
        let markerURL = ownedDirectory.appendingPathComponent(OrphanedBenchmarkCleanupService.markerFilename, isDirectory: false)
        progress(.init(phase: .preparing, completedBytes: 0, totalBytes: configuration.sizeBytes, message: "Creating an isolated benchmark workspace"))

        guard !FileManager.default.fileExists(atPath: ownedDirectory.path) else { throw BenchmarkError.pathAlreadyExists }
        do { try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: false) }
        catch { throw BenchmarkError.createDirectoryFailed }
        try SafeTemporaryPath.validateOwnedDirectory(ownedDirectory, mountRoot: mountRoot)

        var fileIdentity: FileIdentity?
        var markerIdentity: FileIdentity?
        var cleanupStatus: CleanupStatus = .failed
        do {
            let markerFD = try exclusiveCreate(path: markerURL.path)
            let markerHandle = FileHandle(fileDescriptor: markerFD, closeOnDealloc: true)
            let markerData = try JSONEncoder().encode(BenchmarkOwnershipMarker(token: token))
            try markerHandle.write(contentsOf: markerData)
            try durableSynchronize(handle: markerHandle, fd: markerFD)
            try markerHandle.close()
            markerIdentity = try SafeTemporaryPath.identity(of: markerURL)

            let fd = try exclusiveCreate(path: fileURL.path)
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            fileIdentity = try SafeTemporaryPath.identity(of: fileURL)

            var expectedHasher = SHA256Digest()
            let writeStart = DispatchTime.now().uptimeNanoseconds
            var lastSampleTime = writeStart
            var lastSampleBytes: UInt64 = 0
            var written: UInt64 = 0
            var writeSamples: [ThroughputSample] = []
            var chunkIndex: UInt64 = 0

            while written < configuration.sizeBytes {
                try Task.checkCancellation()
                let remaining = configuration.sizeBytes - written
                let count = Int(min(UInt64(chunkSize), remaining))
                let bytes = makeData(count: count, seed: configuration.customSeed, index: chunkIndex, pattern: configuration.dataPattern)
                let data = Data(bytes)
                do { try handle.write(contentsOf: data) }
                catch { throw BenchmarkError.writeFailed(error.localizedDescription) }
                expectedHasher.update(data)
                written += UInt64(count)
                chunkIndex += 1
                let now = DispatchTime.now().uptimeNanoseconds
                if seconds(from: lastSampleTime, to: now) >= configuration.sampleIntervalSeconds || written == configuration.sizeBytes {
                    let elapsed = seconds(from: lastSampleTime, to: now)
                    let delta = written - lastSampleBytes
                    let rate = StorageFormatting.decimalMBPerSecond(bytes: delta, seconds: elapsed)
                    writeSamples.append(.init(elapsedSeconds: seconds(from: writeStart, to: now), megabytesPerSecond: rate, phase: .writing))
                    progress(.init(phase: .writing, completedBytes: written, totalBytes: configuration.sizeBytes, currentMegabytesPerSecond: rate, message: "Writing non-compressible benchmark data"))
                    lastSampleTime = now
                    lastSampleBytes = written
                }
                await Task.yield()
            }

            progress(.init(phase: .flushing, completedBytes: written, totalBytes: configuration.sizeBytes, message: "Flushing writes to durable storage"))
            do { try durableSynchronize(handle: handle, fd: fd) }
            catch { throw BenchmarkError.flushFailed(error.localizedDescription) }
            let writeEnd = DispatchTime.now().uptimeNanoseconds
            let writeDuration = seconds(from: writeStart, to: writeEnd)
            let expectedDigest = expectedHasher.finalizeHex()
            try handle.close()

            try Task.checkCancellation()
            let readHandle: FileHandle
            do { readHandle = try FileHandle(forReadingFrom: fileURL) }
            catch { throw BenchmarkError.readFailed(error.localizedDescription) }
            defer { try? readHandle.close() }

            let readStart = DispatchTime.now().uptimeNanoseconds
            lastSampleTime = readStart
            lastSampleBytes = 0
            var read: UInt64 = 0
            var readSamples: [ThroughputSample] = []
            var actualHasher = SHA256Digest()

            while read < configuration.sizeBytes {
                try Task.checkCancellation()
                let remaining = configuration.sizeBytes - read
                let count = Int(min(UInt64(chunkSize), remaining))
                let data: Data
                do { data = try readHandle.read(upToCount: count) ?? Data() }
                catch { throw BenchmarkError.readFailed(error.localizedDescription) }
                guard !data.isEmpty else { throw BenchmarkError.readFailed("Unexpected end of file") }
                actualHasher.update(data)
                read += UInt64(data.count)
                let now = DispatchTime.now().uptimeNanoseconds
                if seconds(from: lastSampleTime, to: now) >= configuration.sampleIntervalSeconds || read >= configuration.sizeBytes {
                    let elapsed = seconds(from: lastSampleTime, to: now)
                    let delta = read - lastSampleBytes
                    let rate = StorageFormatting.decimalMBPerSecond(bytes: delta, seconds: elapsed)
                    readSamples.append(.init(elapsedSeconds: seconds(from: readStart, to: now), megabytesPerSecond: rate, phase: .reading))
                    progress(.init(phase: .reading, completedBytes: min(read, configuration.sizeBytes), totalBytes: configuration.sizeBytes, currentMegabytesPerSecond: rate, message: "Reading the benchmark file back"))
                    lastSampleTime = now
                    lastSampleBytes = read
                }
                await Task.yield()
            }
            let readEnd = DispatchTime.now().uptimeNanoseconds
            let readDuration = seconds(from: readStart, to: readEnd)
            progress(.init(phase: .verifying, completedBytes: configuration.sizeBytes, totalBytes: configuration.sizeBytes, message: "Verifying SHA-256 integrity"))
            let actualDigest = actualHasher.finalizeHex()
            let integrity = IntegrityResult(status: expectedDigest == actualDigest ? .passed : .mismatch, expectedDigest: expectedDigest, actualDigest: actualDigest)
            var smallFileResult: SmallFileResult?
            if configuration.includeSmallFileWorkload {
                progress(.init(phase: .smallFiles, completedBytes: 0, totalBytes: 1, message: "Running bounded small-file workload"))
                smallFileResult = try runSmallFileWorkload(in: ownedDirectory)
            }

            progress(.init(phase: .cleaningUp, completedBytes: configuration.sizeBytes, totalBytes: configuration.sizeBytes, message: "Removing only FlashScope-owned benchmark data"))
            cleanupStatus = try cleanup(fileURL: fileURL, fileIdentity: fileIdentity, markerURL: markerURL, markerIdentity: markerIdentity, directory: ownedDirectory, mountRoot: mountRoot)
            progress(.init(phase: .completed, completedBytes: configuration.sizeBytes, totalBytes: configuration.sizeBytes, message: "Benchmark complete and cleanup verified"))

            return BenchmarkResult(
                configuration: configuration,
                writeMegabytesPerSecond: StorageFormatting.decimalMBPerSecond(bytes: configuration.sizeBytes, seconds: writeDuration),
                readMegabytesPerSecond: StorageFormatting.decimalMBPerSecond(bytes: configuration.sizeBytes, seconds: readDuration),
                writeDurationSeconds: writeDuration,
                readDurationSeconds: readDuration,
                writeSamples: writeSamples,
                readSamples: readSamples,
                writeStatistics: StatisticsCalculator.calculate(samples: writeSamples.map(\.megabytesPerSecond)),
                readStatistics: StatisticsCalculator.calculate(samples: readSamples.map(\.megabytesPerSecond)),
                integrity: integrity,
                smallFileResult: smallFileResult,
                durableFlushIncluded: true,
                readMayBeCached: true,
                cleanupStatus: cleanupStatus,
                ioErrorCount: 0
            )
        } catch {
            do {
                _ = try cleanup(fileURL: fileURL, fileIdentity: fileIdentity, markerURL: markerURL, markerIdentity: markerIdentity, directory: ownedDirectory, mountRoot: mountRoot)
            } catch let cleanupError {
                throw BenchmarkError.cleanupFailed("Original error: \(error.localizedDescription). Cleanup error: \(cleanupError.localizedDescription)")
            }
            throw error
        }
    }

    private func runSmallFileWorkload(in ownedDirectory: URL) throws -> SmallFileResult {
        let sizes = [4 * 1_024, 64 * 1_024, 1 * 1_024 * 1_024]
        let repetitions = 8
        let totalFiles = sizes.count * repetitions
        var totalBytes: UInt64 = 0
        let start = DispatchTime.now().uptimeNanoseconds
        var created: [(URL, FileIdentity)] = []
        defer {
            for (url, _) in created.reversed() { _ = unlink(url.path) }
        }
        for repetition in 0..<repetitions {
            for size in sizes {
                let url = ownedDirectory.appendingPathComponent("small-\(repetition)-\(size).bin")
                let fd = try exclusiveCreate(path: url.path)
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                let data = Data(makeData(count: size, seed: UInt64(repetition + size), index: 0, pattern: .deterministicPseudoRandom))
                try handle.write(contentsOf: data)
                try durableSynchronize(handle: handle, fd: fd)
                try handle.close()
                let identity = try SafeTemporaryPath.identity(of: url)
                created.append((url, identity))
                let readHandle = try FileHandle(forReadingFrom: url)
                _ = try readHandle.readToEnd()
                try readHandle.close()
                totalBytes += UInt64(size)
            }
        }
        for (url, identity) in created.reversed() {
            try SafeTemporaryPath.validateFile(url, expectedIdentity: identity)
            guard unlink(url.path) == 0 else { throw BenchmarkError.cleanupFailed("Could not delete bounded small-file test item") }
        }
        created.removeAll()
        let duration = seconds(from: start, to: DispatchTime.now().uptimeNanoseconds)
        let operations = Double(totalFiles * 4) // create/write, flush, read, delete
        return SmallFileResult(
            totalBytes: totalBytes,
            fileCount: totalFiles,
            megabytesPerSecond: StorageFormatting.decimalMBPerSecond(bytes: totalBytes, seconds: duration),
            filesPerSecond: Double(totalFiles) / max(duration, 0.000_001),
            operationsPerSecond: operations / max(duration, 0.000_001)
        )
    }

    private func exclusiveCreate(path: String) throws -> Int32 {
        let fd = path.withCString { open($0, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR) }
        guard fd >= 0 else { throw BenchmarkError.createFileFailed }
        return fd
    }

    private func durableSynchronize(handle: FileHandle, fd: Int32) throws {
        try handle.synchronize()
        #if canImport(Darwin)
        if fcntl(fd, F_FULLFSYNC) != 0, fsync(fd) != 0 { throw POSIXError(.EIO) }
        #else
        if fsync(fd) != 0 { throw POSIXError(.EIO) }
        #endif
    }

    private func cleanup(fileURL: URL, fileIdentity: FileIdentity?, markerURL: URL, markerIdentity: FileIdentity?, directory: URL, mountRoot: URL) throws -> CleanupStatus {
        try SafeTemporaryPath.validateOwnedDirectory(directory, mountRoot: mountRoot)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let fileIdentity else { throw BenchmarkError.cleanupFailed("Missing benchmark file identity") }
            try SafeTemporaryPath.validateFile(fileURL, expectedIdentity: fileIdentity)
            guard unlink(fileURL.path) == 0 else { throw BenchmarkError.cleanupFailed("Could not unlink the exact benchmark file") }
        }
        if FileManager.default.fileExists(atPath: markerURL.path) {
            guard let markerIdentity else { throw BenchmarkError.cleanupFailed("Missing ownership marker identity") }
            try SafeTemporaryPath.validateFile(markerURL, expectedIdentity: markerIdentity)
            guard unlink(markerURL.path) == 0 else { throw BenchmarkError.cleanupFailed("Could not unlink the exact ownership marker") }
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try SafeTemporaryPath.validateOwnedDirectory(directory, mountRoot: mountRoot)
            guard rmdir(directory.path) == 0 else { throw BenchmarkError.cleanupFailed("Benchmark directory was not empty or could not be removed") }
        }
        let gone = !FileManager.default.fileExists(atPath: fileURL.path) && !FileManager.default.fileExists(atPath: directory.path)
        guard gone else { throw BenchmarkError.cleanupFailed("Cleanup verification failed") }
        return .verified
    }

    private func makeData(count: Int, seed: UInt64, index: UInt64, pattern: BenchmarkDataPattern) -> [UInt8] {
        switch pattern {
        case .deterministicPseudoRandom:
            var generator = SplitMix64(seed: seed &+ index &* 0x9E3779B97F4A7C15)
            var result = [UInt8](repeating: 0, count: count)
            var offset = 0
            while offset < count {
                var value = generator.next().littleEndian
                withUnsafeBytes(of: &value) { bytes in
                    let copyCount = min(bytes.count, count - offset)
                    result.replaceSubrange(offset..<(offset + copyCount), with: bytes.prefix(copyCount))
                    offset += copyCount
                }
            }
            return result
        case .cryptographicallyRandom:
            var generator = SystemRandomNumberGenerator()
            return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
    }

    private func seconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000_000.0
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
