import FlashScopeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Benchmark") {
                Picker("Default size", selection: $preferences.defaultPreset) {
                    Text("Quick — 256 MiB").tag(BenchmarkPreset.quick)
                    Text("Standard — 1 GiB").tag(BenchmarkPreset.standard)
                    Text("Extended — 4 GiB").tag(BenchmarkPreset.extended)
                }
                HStack {
                    Text("Sample interval")
                    Slider(value: $preferences.sampleInterval, in: 0.1...2.0, step: 0.1)
                    Text(String(format: "%.1f s", preferences.sampleInterval)).monospacedDigit().frame(width: 44)
                }
                Toggle("Enable small-file workload by default", isOn: $preferences.includeSmallFileTest)
                Picker("Throughput units", selection: $preferences.throughputUnit) {
                    ForEach(ThroughputUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Privacy & History") {
                Picker("History retention", selection: $preferences.historyRetention) {
                    ForEach(AppPreferences.HistoryRetention.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Redact device identifiers in exports", isOn: $preferences.redactIdentifiers)
                Toggle("Check safely identifiable orphaned benchmark data on launch", isOn: $preferences.automaticCleanupChecks)
                Text("Reports are never uploaded. Filenames and directory listings are not collected. Usernames in mount paths are always redacted in normal exports.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Advanced") {
                Toggle("Enable raw-device read test", isOn: $preferences.advancedRawReadEnabled)
                    .disabled(!preferences.rawReadHelperAvailable)
                Text("Unavailable in this build. No privileged helper is installed and FlashScope does not fall back to sudo, arbitrary commands, or raw writes. Standard file-level diagnostics remain fully usable.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppPreferences.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560, height: 530)
        .navigationTitle("FlashScope Settings")
    }
}
