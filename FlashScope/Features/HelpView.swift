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
                    helpSection("Start with the verdict", "Overview is intentionally plain-English: it shows the most likely cause, diagnostic confidence, four separate dimensions (media, connection, filesystem, performance), evidence coverage, and the safest next step before exposing raw technical detail.")
                    helpSection("Quick, Standard, Deep, Capacity Integrity", "Quick is a short first pass. Standard is the normal balanced check. Deep writes more data so sustained slowdowns and instability are easier to observe. Capacity Integrity uses the largest safe sample permitted by the current free-space policy. It never overwrites occupied space, so a passing sample proves only the tested free area—not capacity that FlashScope did not touch.")
                    helpSection("Connection-path diagnosis", "FlashScope keeps declared USB capability separate from the currently negotiated link. The Connection view visualizes the Mac → hub/adapter → negotiated link → drive path and highlights a reduced link as a connection bottleneck rather than automatically blaming flash media.")
                    helpSection("Fix and retest", "Actionable findings include a controlled diagnostic experiment. Change one variable—such as removing a hub, freeing space, or changing ports—then rerun the same diagnostic profile. Device Timeline compares the latest result with prior runs so improvement or regression is visible.")
                    helpSection("Cache cliff and stability", "A drive can start fast and become much slower after its write cache is exhausted. FlashScope analyzes the beginning and end of sustained write samples, reports a probable cache cliff when the drop is large, and computes a stability score from variation, deep stalls, and I/O errors.")
                    helpSection("Workload fit", "Choose your typical workload in Settings. FlashScope interprets measured performance differently for general storage, photos/documents, large video, backups, many small files, or developer projects. These are practical guidance—not guarantees for a specific codec, application, or workload.")
                    helpSection("Community intelligence privacy", "The optional community-baseline setting does not upload anything in this build. It only enables a privacy-minimized contribution payload you can copy from Export. The payload excludes filenames, directory listings, clear serial numbers, and user paths.")
                    helpSection("Technician mode", "Technician mode exposes additional raw evidence, evidence coverage, local history context, and conservative PASS/REVIEW/FAIL triage. This is operational triage, not a warranty or future-reliability certification.")
                    helpSection("Data safety", "Standard inspection is read-only. A benchmark begins only after you explicitly start it. It creates a unique app-owned directory, never overwrites an existing path, verifies file identity before deletion, rejects symlinks, and never formats, repartitions, repairs, force-unmounts, or raw-writes a disk.")
                    helpSection("Filesystem verification", "Verification is separate from repair. FlashScope asks before a normal unmount, never force-unmounts, runs only the allowlisted macOS verification operation, records its exit status, and attempts to remount. Failure to run is reported as inconclusive rather than corruption.")
                    helpSection("SMART and USB bridges", "Many USB flash drives and bridge controllers do not expose SMART. FlashScope reports this as unavailable and reduces diagnostic confidence; it does not treat missing SMART as a failure.")
                    helpSection("Benchmarks and caches", "Write throughput includes durable synchronization. Standard read testing is file-level and may be influenced by macOS caches. FlashScope labels that limitation and does not claim raw-media throughput without a separately secured capability.")
                    helpSection("Backups", "Diagnostics reduce uncertainty but cannot guarantee future reliability. Keep independent backups of important data, especially after integrity mismatches, repeated I/O errors, or filesystem problems.")
                }.padding(20)
            }
        }
        .frame(minWidth: 680, minHeight: 620)
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
