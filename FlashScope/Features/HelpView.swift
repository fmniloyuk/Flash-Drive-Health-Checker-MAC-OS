import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("FlashScope Help", systemImage: "lifepreserver.fill").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helpSection("What FlashScope tells you", "FlashScope separates the device’s declared USB capability, the currently negotiated link, practical bus expectations, measured flash throughput, filesystem state, and available hardware-health signals. A slow USB 2.0 device is not automatically a failing device.")
                    helpSection("Data safety", "Standard inspection is read-only. A benchmark begins only after you press the explicit start button. It creates a unique app-owned directory, never overwrites an existing path, verifies the test file identity before deletion, rejects symlinks, and never formats, repartitions, repairs, force-unmounts, or raw-writes a disk.")
                    helpSection("Filesystem verification", "Verification is separate from repair. FlashScope asks before a normal unmount, never force-unmounts, runs only the allowlisted macOS verification operation, records its exit status, and attempts to remount. Failure to run is reported as inconclusive rather than corruption.")
                    helpSection("SMART and USB bridges", "Many USB flash drives and bridge controllers do not expose SMART. FlashScope reports this as ‘Not supported or not exposed’ and reduces diagnostic confidence; it does not treat missing SMART as a failure.")
                    helpSection("Benchmarks and caches", "Write throughput includes durable synchronization. Standard read testing is file-level and may be influenced by caches, especially for small test files. FlashScope labels that limitation and does not claim raw-media throughput without a separately secured capability.")
                    helpSection("Backups", "Diagnostics can reduce uncertainty, but no health score can guarantee future storage reliability. Keep independent backups of important data, especially after integrity mismatches or repeated I/O errors.")
                }.padding(20)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
