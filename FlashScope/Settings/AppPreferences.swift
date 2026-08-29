import Foundation
import FlashScopeCore
import Observation
import SwiftUI

@MainActor
@Observable
final class AppPreferences {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self { case .system: nil; case .light: .light; case .dark: .dark }
        }
    }

    enum HistoryRetention: Int, CaseIterable, Identifiable {
        case days30 = 30
        case days90 = 90
        case year = 365
        case forever = 0
        var id: Int { rawValue }
        var title: String { self == .forever ? "Forever" : "\(rawValue) days" }
    }

    private let defaults: UserDefaults

    var defaultPreset: BenchmarkPreset { didSet { defaults.set(defaultPreset.rawValue, forKey: "defaultPreset") } }
    var sampleInterval: Double { didSet { defaults.set(sampleInterval, forKey: "sampleInterval") } }
    var includeSmallFileTest: Bool { didSet { defaults.set(includeSmallFileTest, forKey: "includeSmallFileTest") } }
    var historyRetention: HistoryRetention { didSet { defaults.set(historyRetention.rawValue, forKey: "historyRetention") } }
    var redactIdentifiers: Bool { didSet { defaults.set(redactIdentifiers, forKey: "redactIdentifiers") } }
    var automaticCleanupChecks: Bool { didSet { defaults.set(automaticCleanupChecks, forKey: "automaticCleanupChecks") } }
    var throughputUnit: ThroughputUnit { didSet { defaults.set(throughputUnit.rawValue, forKey: "throughputUnit") } }
    var workload: StorageWorkload { didSet { defaults.set(workload.rawValue, forKey: "workload") } }
    var anonymousIntelligenceOptIn: Bool { didSet { defaults.set(anonymousIntelligenceOptIn, forKey: "anonymousIntelligenceOptIn") } }
    var technicianMode: Bool { didSet { defaults.set(technicianMode, forKey: "technicianMode") } }
    var advancedRawReadEnabled: Bool { didSet { defaults.set(false, forKey: "advancedRawReadEnabled") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }

    let rawReadHelperAvailable = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultPreset = BenchmarkPreset(rawValue: defaults.string(forKey: "defaultPreset") ?? "") ?? .standard
        let savedInterval = defaults.double(forKey: "sampleInterval")
        sampleInterval = savedInterval > 0 ? max(0.1, min(5.0, savedInterval)) : 0.5
        includeSmallFileTest = defaults.object(forKey: "includeSmallFileTest") as? Bool ?? false
        historyRetention = HistoryRetention(rawValue: defaults.integer(forKey: "historyRetention")) ?? .days90
        redactIdentifiers = defaults.object(forKey: "redactIdentifiers") as? Bool ?? true
        automaticCleanupChecks = defaults.object(forKey: "automaticCleanupChecks") as? Bool ?? true
        throughputUnit = ThroughputUnit(rawValue: defaults.string(forKey: "throughputUnit") ?? "") ?? .megabytesPerSecond
        workload = StorageWorkload(rawValue: defaults.string(forKey: "workload") ?? "") ?? .general
        anonymousIntelligenceOptIn = defaults.object(forKey: "anonymousIntelligenceOptIn") as? Bool ?? false
        technicianMode = defaults.object(forKey: "technicianMode") as? Bool ?? false
        advancedRawReadEnabled = false
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    }
}
