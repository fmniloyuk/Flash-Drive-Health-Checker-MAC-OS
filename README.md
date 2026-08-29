# FlashScope

FlashScope is a native macOS USB-storage diagnostic application built to answer a practical question:

> **Why is this removable drive slow, unreliable, full, read-only, disconnecting, or otherwise behaving badly — and what can I safely do next?**

It combines USB connection evidence, filesystem state, bounded read/write testing, SHA-256 integrity verification, transfer-stability analysis, local history, and explainable diagnostic rules into a verdict-first troubleshooting experience.

> **Safety first:** FlashScope never automatically formats, repartitions, repairs, force-unmounts, erases, or deletes user files. Benchmark writes are limited to uniquely named FlashScope-owned temporary data and use guarded cleanup logic.

## FlashScope 2

### Verdict-first dashboard

The Overview screen leads with the conclusion rather than a wall of telemetry. It shows:

- the current classification and diagnostic confidence
- the most likely cause and safest next action
- separate Media reliability, Connection, Filesystem, and Performance dimensions
- Evidence Coverage so unavailable telemetry is not mistaken for failure
- same-device historical comparison when prior tests exist

A low evidence percentage does **not** mean the drive is unhealthy. SMART, power, topology, or other USB data may simply be hidden by a removable-device bridge.

The dashboard has three modes:

- **Overview** — verdict, key evidence, findings, performance, and timeline
- **Diagnose** — connection/filesystem evidence plus guided fix → retest experiments
- **Technical** — raw exposed evidence, evidence coverage, and conservative technician triage

Technician PASS / REVIEW / FAIL is local operational triage, not a warranty or a guarantee of future reliability.

## Guided diagnostic profiles

FlashScope exposes four safe diagnostic profiles:

- **Quick** — a short first-pass sample for connection troubleshooting and integrity evidence.
- **Standard** — balanced sequential read/write testing with durable write synchronization, SHA-256 readback verification, and optional small-file testing.
- **Deep** — a longer sustained workload intended to reveal stalls, instability, and write-cache slowdowns more clearly.
- **Capacity Integrity** — the largest currently safe free-space sample permitted by FlashScope's benchmark policy.

Capacity Integrity remains non-destructive. It never overwrites occupied regions or existing user files. A passing result proves only the temporary sample that was actually written and read back; it does **not** claim that occupied or otherwise untested capacity was physically verified. FAT32 can also limit the size of a single test file.

## Explainable diagnostics

FlashScope correlates evidence rather than treating every number independently. Examples include:

- USB 3-capable hardware currently negotiated at USB 2-class speed
- performance consistent with a normal USB 2-class ceiling instead of failed flash
- healthy reads but unusually slow sustained writes
- a probable write-cache cliff: fast burst followed by a large sustained drop
- unstable throughput or deep stalls
- small-file overhead versus large sequential performance
- local historical regression for the same privacy-preserving drive identity
- nearly-full or read-only volume
- filesystem-verification issues
- benchmark integrity mismatch
- repeated I/O errors
- possible insufficient USB power
- hub/adapter bottlenecks

Findings include severity, confidence, explanation, expected impact, safe action, caveat, and the evidence used.

## Fix → retest workflow

Actionable findings can include a controlled diagnostic experiment. For example, when the connection appears to be the bottleneck FlashScope can suggest removing an intermediate hub, reconnecting to a known high-speed port, and rerunning the **same** profile. The Device Timeline then compares results so improvement or regression is visible instead of relying on memory.

## USB connection path

The Connection view turns exposed topology into an understandable path such as:

```text
Mac → Hub / adapter → Negotiated link → USB device
```

Declared USB capability remains separate from the negotiated link. If macOS does not expose a value, FlashScope says so rather than inventing it.

## Performance intelligence

FlashScope interprets measured MB/s in context instead of presenting peak throughput as a universal health score.

It can show:

- measured versus the broad practical range expected from the current connection
- whether the bus is a plausible bottleneck
- transfer-stability score and throughput variation
- deep-stall count and I/O-error context
- burst-versus-tail write behavior
- probable sustained write-cache cliff and an estimated cliff point when enough samples exist
- estimated transfer times for common data sizes

FlashScope does not claim thermal throttling without temperature evidence and does not label file-level reads as raw-media performance.

## Workload suitability

Choose the workload that matters to you:

- General storage
- Photos & documents
- Large video files
- Backup
- Many small files
- Developer projects

Small-file workloads use measured files/s when available instead of pretending sequential MB/s tells the whole story. Suitability guidance is practical interpretation, not a guarantee for a specific application, codec, or workflow.

## Device Timeline

Completed checks are stored locally using a privacy-preserving device identity. The timeline can show read/write trends, stability changes, integrity outcomes, profile/date context, and fix/retest deltas.

Same-device history is often more useful than comparing a flash drive with an overly broad generic benchmark.

## Evidence reports

FlashScope can export:

- PDF evidence report
- JSON diagnostic report
- plain-text **Diagnostic Evidence Certificate**
- redacted support certificate copied to the clipboard

The evidence certificate records the verdict, confidence, evidence coverage, cause/action, connection state, performance/integrity/stability evidence, filesystem result, findings, limitations, methodology, and safety caveats.

## Privacy-minimized intelligence foundation

FlashScope includes an **explicit opt-in, local-only foundation** for a possible future community baseline network.

When enabled in Settings, Export can prepare a privacy-minimized JSON contribution and copy it to the clipboard. **This build does not automatically upload anything and does not include a community backend/server.**

The payload can include useful aggregate diagnostic fields such as device-family metadata, capacity/filesystem, VID/PID, exposed USB capability/link speed, hub presence, read/write performance, variation, integrity outcome, I/O error count, and diagnosis categories. It intentionally excludes filenames, file contents, user-specific paths, and cleartext serial numbers.

## Missing evidence is not failure

USB flash drives, enclosures, docks, hubs, adapters, and bridge controllers expose different amounts of telemetry to macOS. FlashScope follows a strict rule:

**If macOS does not expose evidence safely, FlashScope does not invent it.**

Missing evidence may reduce confidence, but it is not itself proof of a failing device.

## Safe remediation

FlashScope recommends reversible next steps rather than silently modifying disks. Examples:

- nearly full → open the drive in Finder, free space manually, refresh, and retest
- read-only → inspect hardware write protection or open Disk Utility
- filesystem issue → back up important data first, then inspect with Disk Utility
- reduced USB link → simplify the connection path or use another known high-speed port
- missing USB telemetry → refresh, reconnect, simplify hubs/adapters, or compare macOS System Information

FlashScope never automatically deletes user files, repairs a filesystem, changes filesystem type, repartitions, or reformats a drive.

## Safe benchmark engine

The benchmark engine:

- rejects internal disks and read-only volumes
- requires an eligible mounted removable target
- keeps a free-space reserve and limits test size relative to available capacity
- uses non-zero deterministic pseudo-random or cryptographically random data
- measures sequential writes and reads and can optionally measure small-file behavior
- durably synchronizes writes before verification
- calculates SHA-256 while writing and on complete readback
- tracks I/O errors
- validates ownership metadata before cleanup
- rejects symlinks and unexpected cleanup targets
- removes only the exact FlashScope-owned workspace
- applies the same guarded cleanup path during cancellation

FlashScope never benchmarks arbitrary user files.

## Filesystem verification

FlashScope can request a normal, non-forced unmount and run macOS read-only filesystem verification. It does not automatically run repair, force-unmount a busy volume, reformat, or repartition. If verification reports problems, back up important data before considering repair with an appropriate tool.

## Requirements

- macOS 14.0 or later
- a recent Xcode with Swift 6 support for development
- removable USB storage for live diagnostics

FlashScope uses Swift, SwiftUI, SwiftData, Charts, Disk Arbitration, IOKit, Foundation, and AppKit.

## Project structure

```text
FlashScope/                  macOS application UI and platform services
Sources/FlashScopeCore/      Portable diagnostics, benchmark, and intelligence core
Tests/                       Portable core unit tests
FlashScopeIntegrationTests/  macOS integration tests
FlashScopeUITests/           UI tests
Scripts/                     Build/distribution tools
FlashScope.xcodeproj/        Xcode project
```

## Build and test

```bash
git clone https://github.com/fmniloyuk/Flash-Drive-Health-Checker-MAC-OS.git
cd Flash-Drive-Health-Checker-MAC-OS
swift test -c debug
```

Native macOS test suite:

```bash
xcodebuild \
  -project FlashScope.xcodeproj \
  -scheme FlashScope \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .artifacts/DerivedData \
  PRODUCT_BUNDLE_IDENTIFIER=com.example.FlashScope \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

Build the app:

```bash
xcodebuild \
  -project FlashScope.xcodeproj \
  -scheme FlashScope \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .artifacts/DerivedData \
  PRODUCT_BUNDLE_IDENTIFIER=com.example.FlashScope \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

open .artifacts/DerivedData/Build/Products/Debug/FlashScope.app
```

## Simulation mode

Debug builds include deterministic fixtures so UI and diagnostic behavior can be tested without touching a real USB drive:

```bash
open .artifacts/DerivedData/Build/Products/Debug/FlashScope.app --args --simulate
open .artifacts/DerivedData/Build/Products/Debug/FlashScope.app --args --simulate-empty
```

## Build a DMG

```bash
chmod +x Scripts/build_dmg.sh
./Scripts/build_dmg.sh
```

When tests have already run:

```bash
./Scripts/build_dmg.sh --skip-tests
```

Outputs:

```text
.artifacts/dist/FlashScope.app
.artifacts/dist/FlashScope.dmg
```

## Signing and notarization

Unsigned builds are suitable for local development. Public distribution should use the distributor's real Developer ID identity and notarization credentials; the build scripts never invent or store them.

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
BUNDLE_ID='com.yourcompany.FlashScope' \
./Scripts/build_dmg.sh --sign
```

With a configured `notarytool` profile:

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
BUNDLE_ID='com.yourcompany.FlashScope' \
NOTARY_PROFILE='flashscope-notary' \
./Scripts/build_dmg.sh --sign --notarize
```

## GitHub Actions and releases

`.github/workflows/macos-release.yml` runs portable core tests and the native Xcode suite on a macOS runner, builds the Release app/DMG, produces a SHA-256 checksum, and uploads the artifacts. A `v*` tag creates or updates a GitHub Release.

## Privacy

Core diagnostics, diagnosis, history, and reports run locally. Reports can redact identifying details. No cloud service is required.

## Safety philosophy

**Observe first. Measure safely. Explain the evidence. Recommend a reversible next step. Retest the hypothesis. Never perform destructive remediation automatically.**

## Disclaimer

FlashScope is a diagnostic utility, not a substitute for backups. Storage can fail without warning. If FlashScope reports integrity mismatches, repeated I/O errors, or other critical evidence, back up important data immediately.
