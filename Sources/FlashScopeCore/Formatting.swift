import Foundation

public enum ThroughputUnit: String, Codable, CaseIterable, Sendable {
    case megabytesPerSecond = "MB/s"
    case mebibytesPerSecond = "MiB/s"
}

public enum StorageWorkload: String, Codable, CaseIterable, Sendable {
    case general = "General storage"
    case photosDocuments = "Photos & documents"
    case largeVideo = "Large video files"
    case backup = "Backup"
    case manySmallFiles = "Many small files"
    case developerProjects = "Developer projects"
}

public enum SuitabilityRating: String, Codable, Sendable {
    case good = "Good fit"
    case mixed = "Usable with caveats"
    case poor = "Likely frustrating"
    case unknown = "Needs a benchmark"
}

public struct WorkloadSuitability: Codable, Equatable, Sendable {
    public var workload: StorageWorkload
    public var rating: SuitabilityRating
    public var summary: String

    public init(workload: StorageWorkload, rating: SuitabilityRating, summary: String) {
        self.workload = workload
        self.rating = rating
        self.summary = summary
    }
}

public struct EvidenceCoverageSummary: Codable, Equatable, Sendable {
    public var availableSignals: Int
    public var totalSignals: Int
    public var available: [String]
    public var missing: [String]

    public init(availableSignals: Int, totalSignals: Int, available: [String], missing: [String]) {
        self.availableSignals = availableSignals
        self.totalSignals = totalSignals
        self.available = available
        self.missing = missing
    }

    public var fraction: Double {
        guard totalSignals > 0 else { return 0 }
        return Double(availableSignals) / Double(totalSignals)
    }

    public var percentage: Int { Int((fraction * 100).rounded()) }
}

public struct CacheCliffAnalysis: Codable, Equatable, Sendable {
    public var detected: Bool
    public var burstMegabytesPerSecond: Double
    public var sustainedMegabytesPerSecond: Double
    public var dropPercent: Int
    public var estimatedCliffBytes: UInt64?

    public init(detected: Bool, burstMegabytesPerSecond: Double, sustainedMegabytesPerSecond: Double, dropPercent: Int, estimatedCliffBytes: UInt64?) {
        self.detected = detected
        self.burstMegabytesPerSecond = burstMegabytesPerSecond
        self.sustainedMegabytesPerSecond = sustainedMegabytesPerSecond
        self.dropPercent = dropPercent
        self.estimatedCliffBytes = estimatedCliffBytes
    }
}

public struct TransferStabilityAnalysis: Codable, Equatable, Sendable {
    public var score: Int
    public var label: String
    public var variationPercent: Int
    public var stallCount: Int

    public init(score: Int, label: String, variationPercent: Int, stallCount: Int) {
        self.score = min(100, max(0, score))
        self.label = label
        self.variationPercent = max(0, variationPercent)
        self.stallCount = max(0, stallCount)
    }
}

public struct LocalPerformanceComparison: Codable, Equatable, Sendable {
    public var historicalAverageWriteMBps: Double
    public var historicalAverageReadMBps: Double
    public var writeChangePercent: Double
    public var readChangePercent: Double

    public init(historicalAverageWriteMBps: Double, historicalAverageReadMBps: Double, writeChangePercent: Double, readChangePercent: Double) {
        self.historicalAverageWriteMBps = historicalAverageWriteMBps
        self.historicalAverageReadMBps = historicalAverageReadMBps
        self.writeChangePercent = writeChangePercent
        self.readChangePercent = readChangePercent
    }
}

public enum StorageFormatting {
    public static func decimalMBPerSecond(bytes: UInt64, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) / 1_000_000.0 / seconds
    }

    public static func binaryMiBPerSecond(bytes: UInt64, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) / 1_048_576.0 / seconds
    }

    public static func throughput(_ decimalMBps: Double, unit: ThroughputUnit) -> Double {
        switch unit {
        case .megabytesPerSecond: decimalMBps
        case .mebibytesPerSecond: decimalMBps * 1_000_000.0 / 1_048_576.0
        }
    }

    public static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total < 60 { return "~\(max(1, total)) sec" }
        let minutes = total / 60
        if minutes < 60 { return "~\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "~\(hours) hr" : "~\(hours) hr \(remaining) min"
    }
}

public enum StatisticsCalculator {
    public static func calculate(samples: [Double]) -> BenchmarkStatistics {
        guard !samples.isEmpty else {
            return .init(minimum: 0, average: 0, median: 0, p95: 0, maximum: 0, coefficientOfVariation: 0)
        }
        let sorted = samples.sorted()
        let count = sorted.count
        let average = sorted.reduce(0, +) / Double(count)
        let median: Double = count.isMultiple(of: 2)
            ? (sorted[count / 2 - 1] + sorted[count / 2]) / 2
            : sorted[count / 2]
        let p95Index = max(0, min(count - 1, Int(ceil(Double(count) * 0.95)) - 1))
        let variance = sorted.reduce(0) { $0 + pow($1 - average, 2) } / Double(count)
        let cv = average > 0 ? sqrt(variance) / average : 0
        return .init(
            minimum: sorted.first ?? 0,
            average: average,
            median: median,
            p95: sorted[p95Index],
            maximum: sorted.last ?? 0,
            coefficientOfVariation: cv
        )
    }
}

public enum DiagnosticInsightAnalyzer {
    public static func evidenceCoverage(
        drive: PhysicalDrive,
        volume: Volume,
        connection: USBConnection,
        benchmark: BenchmarkResult?,
        filesystemCheck: FilesystemCheckResult,
        healthSignals: [HealthSignal]
    ) -> EvidenceCoverageSummary {
        var available: [String] = []
        var missing: [String] = []

        func record(_ name: String, _ isAvailable: Bool) {
            if isAvailable { available.append(name) } else { missing.append(name) }
        }

        record("USB specification", connection.declaredSpecification.value != nil || drive.capabilities.declaredUSBSpecification.value != nil)
        record("Negotiated link", connection.negotiatedSpeed.value != nil)
        record("USB identity", connection.vendorID.value != nil || connection.productID.value != nil)
        record("USB topology", connection.portPath.value != nil || !connection.topology.isEmpty)
        record("USB power", connection.allocatedMilliAmps.value != nil || connection.availableMilliAmps.value != nil)
        record("Filesystem", volume.filesystem.value != nil)
        record("Partition scheme", volume.partitionScheme.value != nil)
        record("Performance", benchmark != nil)
        record("Data integrity", benchmark?.integrity.status == .passed || benchmark?.integrity.status == .mismatch)
        record("Filesystem verification", filesystemCheck.status != .notRun && filesystemCheck.status != .cancelled)
        record("Hardware health", healthSignals.contains { $0.availability.value != nil })

        return .init(availableSignals: available.count, totalSignals: available.count + missing.count, available: available, missing: missing)
    }

    public static func cacheCliff(for benchmark: BenchmarkResult) -> CacheCliffAnalysis? {
        let samples = benchmark.writeSamples.filter { $0.megabytesPerSecond > 0 }
        guard samples.count >= 6 else { return nil }
        let slice = max(2, samples.count / 3)
        let burstSamples = samples.prefix(slice).map(\.megabytesPerSecond)
        let sustainedSamples = samples.suffix(slice).map(\.megabytesPerSecond)
        let burst = StatisticsCalculator.calculate(samples: burstSamples).median
        let sustained = StatisticsCalculator.calculate(samples: sustainedSamples).median
        guard burst > 0 else { return nil }
        let ratio = sustained / burst
        let drop = Int(max(0, (1 - ratio) * 100).rounded())
        let detected = burst >= 20 && ratio <= 0.55 && drop >= 40

        var cliffBytes: UInt64?
        if detected, let finalElapsed = samples.last?.elapsedSeconds, finalElapsed > 0 {
            let threshold = burst * 0.60
            if let cliff = samples.dropFirst(max(1, samples.count / 5)).first(where: { $0.megabytesPerSecond <= threshold }) {
                let fraction = min(1, max(0, cliff.elapsedSeconds / finalElapsed))
                cliffBytes = UInt64(Double(benchmark.configuration.sizeBytes) * fraction)
            }
        }

        return .init(
            detected: detected,
            burstMegabytesPerSecond: burst,
            sustainedMegabytesPerSecond: sustained,
            dropPercent: drop,
            estimatedCliffBytes: cliffBytes
        )
    }

    public static func stability(for benchmark: BenchmarkResult) -> TransferStabilityAnalysis {
        let all = benchmark.writeSamples.map(\.megabytesPerSecond) + benchmark.readSamples.map(\.megabytesPerSecond)
        let positive = all.filter { $0 > 0 }
        guard !positive.isEmpty else { return .init(score: 0, label: "Unknown", variationPercent: 0, stallCount: 0) }
        let stats = StatisticsCalculator.calculate(samples: positive)
        let median = max(0.1, stats.median)
        let stalls = positive.filter { $0 < median * 0.25 }.count
        let variation = Int((stats.coefficientOfVariation * 100).rounded())
        let score = max(0, min(100, 100 - variation - stalls * 8 - benchmark.ioErrorCount * 20))
        let label: String
        switch score {
        case 85...: label = "Excellent"
        case 70..<85: label = "Good"
        case 50..<70: label = "Variable"
        default: label = "Poor"
        }
        return .init(score: score, label: label, variationPercent: variation, stallCount: stalls)
    }

    public static func workloadSuitability(_ workload: StorageWorkload, benchmark: BenchmarkResult?) -> WorkloadSuitability {
        guard let benchmark else {
            return .init(workload: workload, rating: .unknown, summary: "Run a benchmark so FlashScope can interpret this workload against measured performance.")
        }
        let write = benchmark.writeMegabytesPerSecond
        let read = benchmark.readMegabytesPerSecond
        let stability = stability(for: benchmark)

        switch workload {
        case .photosDocuments:
            let rating: SuitabilityRating = write >= 15 && stability.score >= 50 ? .good : (write >= 7 ? .mixed : .poor)
            return .init(workload: workload, rating: rating, summary: rating == .good ? "Measured throughput is generally comfortable for ordinary photos and documents." : "Copies should work, but low sustained writes or instability may make larger folders feel slow.")
        case .largeVideo:
            let rating: SuitabilityRating = write >= 80 && read >= 100 && stability.score >= 70 ? .good : (write >= 30 && read >= 50 ? .mixed : .poor)
            return .init(workload: workload, rating: rating, summary: rating == .good ? "Sustained large-file performance is strong enough for demanding transfers." : "Large video transfers may be limited by sustained write speed, read speed, or stability; validate against the requirements of your specific codec/workflow.")
        case .backup:
            let rating: SuitabilityRating = write >= 30 && benchmark.integrity.status == .passed ? .good : (write >= 15 ? .mixed : .poor)
            return .init(workload: workload, rating: rating, summary: rating == .good ? "Integrity passed and sustained writes are reasonable for routine backup copies." : "Backups may complete slowly; reliability evidence matters more than peak speed, so repeat tests if errors or stalls appear.")
        case .manySmallFiles, .developerProjects:
            guard let small = benchmark.smallFileResult else {
                return .init(workload: workload, rating: .mixed, summary: "Large-file performance is known, but this workload depends heavily on small-file metadata operations. Enable the small-file workload for a better answer.")
            }
            let rating: SuitabilityRating = small.filesPerSecond >= 250 ? .good : (small.filesPerSecond >= 80 ? .mixed : .poor)
            return .init(workload: workload, rating: rating, summary: "Measured small-file rate: \(Int(small.filesPerSecond)) files/s. This is more representative for project trees and folders containing many small files than sequential MB/s alone.")
        case .general:
            let rating: SuitabilityRating = write >= 20 && read >= 30 && stability.score >= 55 ? .good : (write >= 10 ? .mixed : .poor)
            return .init(workload: workload, rating: rating, summary: rating == .good ? "The measured balance of read, write, and stability is suitable for general removable storage." : "The drive is usable, but one or more measured dimensions could make everyday transfers feel slow.")
        }
    }

    public static func estimatedTransferSeconds(bytes: UInt64, megabytesPerSecond: Double) -> Double? {
        guard megabytesPerSecond > 0 else { return nil }
        return Double(bytes) / 1_000_000.0 / megabytesPerSecond
    }

    public static func localComparison(current: BenchmarkResult, history: [BenchmarkResult]) -> LocalPerformanceComparison? {
        let prior = history.filter { $0.configuration.sizeBytes > 0 }
        guard !prior.isEmpty else { return nil }
        let writeAverage = prior.map(\.writeMegabytesPerSecond).reduce(0, +) / Double(prior.count)
        let readAverage = prior.map(\.readMegabytesPerSecond).reduce(0, +) / Double(prior.count)
        let writeChange = writeAverage > 0 ? (current.writeMegabytesPerSecond / writeAverage - 1) * 100 : 0
        let readChange = readAverage > 0 ? (current.readMegabytesPerSecond / readAverage - 1) * 100 : 0
        return .init(
            historicalAverageWriteMBps: writeAverage,
            historicalAverageReadMBps: readAverage,
            writeChangePercent: writeChange,
            readChangePercent: readChange
        )
    }
}
