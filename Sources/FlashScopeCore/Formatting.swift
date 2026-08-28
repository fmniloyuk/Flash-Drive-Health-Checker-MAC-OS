import Foundation

public enum ThroughputUnit: String, Codable, CaseIterable, Sendable {
    case megabytesPerSecond = "MB/s"
    case mebibytesPerSecond = "MiB/s"
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
