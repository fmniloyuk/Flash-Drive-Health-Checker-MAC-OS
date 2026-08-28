# FlashScope

FlashScope is a native macOS USB flash-drive diagnostics application that helps explain **why a removable USB storage device is slow, unreliable, full, read-only, or behaving unexpectedly**.

It combines USB connection evidence, volume/filesystem information, safe performance testing, data-integrity verification, filesystem checks, historical results, and explainable diagnostic findings.

> **Safety first:** FlashScope never automatically formats, repartitions, repairs, force-unmounts, erases, or deletes user files. The only writes performed by a benchmark are clearly scoped application-owned temporary files that are verified and removed through guarded cleanup logic.

## What FlashScope does

### Removable USB discovery

FlashScope automatically discovers supported external/removable USB storage and monitors insertion/removal using native macOS APIs.

Depending on what macOS and the device's USB bridge expose, FlashScope can show:

- Drive/model information
- Capacity and free space
- Mount/write state
- Filesystem and partition scheme
- Declared USB specification
- Negotiated USB link speed
- Theoretical bus ceiling
- Expected practical throughput guidance
- USB topology and hub/adapter presence
- Vendor/product IDs
- USB location identifier
- USB power/current information

### Explainable diagnostics

FlashScope separates **actual detected problems** from **missing diagnostic evidence**.

Examples of actionable findings include:

- Drive is full or nearly full
- Read-only volume
- USB 3-capable device negotiated at USB 2-class speed
- Slow sustained writes
- Unstable throughput
- Small-file overhead
- Filesystem verification issues
- Benchmark integrity mismatch
- Repeated I/O errors
- Possible insufficient USB power
- Hub/adapter bottlenecks

Missing SMART or USB telemetry is treated as a limitation, not as proof of hardware failure.

## Why some USB information can be unavailable

USB flash drives and adapters do not all expose the same telemetry to macOS. A USB bridge may hide SMART data, power information, USB descriptors, or connection details.

FlashScope therefore follows a strict rule:

**If macOS does not expose evidence safely, FlashScope does not invent it.**

The Connection card now hides unavailable metric rows instead of filling the dashboard with repeated `Unavailable` values. When important connection evidence is missing it shows one concise explanation, the underlying reasons in a disclosure section, and safe next steps such as:

- Refresh FlashScope
- Reconnect the drive
- Connect directly to the Mac
- Remove intermediate hubs/adapters where practical
- Open macOS System Information to compare the USB entry

Missing connection evidence lowers diagnostic confidence but is not itself classified as drive failure.

## Safe remediation actions

FlashScope can suggest or open the appropriate macOS tool without taking destructive action itself.

For example:

- **Drive full / nearly full:** Open the mounted drive in Finder, free space manually, then refresh
- **Read-only volume:** Inspect hardware write protection or open Disk Utility
- **Filesystem verification issue:** Back up important data first, then inspect the volume in Disk Utility
- **Reduced USB link:** Reconnect directly to a known high-speed port and refresh
- **Missing USB telemetry:** Refresh, reconnect, or open System Information

FlashScope does **not** automatically delete files, repair filesystems, change filesystem type, or reformat a drive.

## Safe performance testing

FlashScope can perform controlled read/write benchmarks using an application-owned temporary workspace on the selected removable volume.

The benchmark engine:

- Rejects internal disks
- Rejects read-only volumes
- Requires adequate free space
- Keeps a free-space reserve
- Limits benchmark size relative to available capacity
- Uses non-zero deterministic pseudo-random or cryptographic random test data
- Measures sequential writes and reads
- Can optionally measure small-file behavior
- Flushes writes before readback
- Verifies data with SHA-256
- Tracks I/O errors
- Validates ownership metadata before cleanup
- Rejects symlinks and unexpected cleanup targets
- Cleans only the exact FlashScope-owned workspace
- Handles cancellation through the same guarded cleanup path

FlashScope never benchmarks arbitrary user files.

## Data-integrity verification

After benchmark data is written and flushed, FlashScope reads it back and compares SHA-256 digests.

An integrity mismatch is considered critical evidence because it can indicate unreliable storage, connection errors, or corruption. Back up important data immediately if FlashScope reports an integrity mismatch or repeated I/O errors.

## Filesystem verification

FlashScope can request a normal, non-forced unmount and run macOS read-only filesystem verification.

It does not automatically:

- Run filesystem repair
- Force-unmount a busy volume
- Reformat a drive
- Repartition a drive

If verification reports issues, FlashScope recommends backing up important data before considering repair with an appropriate tool.

## FAT32 behavior

FlashScope recognizes FAT32's single-file size limit. FAT32 cannot store one file of 4 GiB or larger, so incompatible extended benchmarks are disabled.

This is a filesystem limitation and is **not** evidence that the flash memory is failing.

## Diagnostic confidence

A diagnostic confidence percentage communicates how much useful evidence was available for the current assessment.

Confidence can be reduced when, for example:

- SMART/media-health telemetry is unavailable
- Negotiated USB link speed is unavailable
- Declared USB specification is unavailable
- No performance benchmark has been run yet
- Filesystem verification could not complete

Unsupported SMART intentionally does not reduce the media-health score; it reduces confidence only.

## Requirements

- macOS 14.0 or later
- Xcode with Swift 6 support for development
- A removable USB storage device for live diagnostics

FlashScope uses native Apple technologies including:

- Swift
- SwiftUI
- SwiftData
- Charts
- Disk Arbitration
- IOKit
- Foundation
- AppKit

## Project structure

```text
FlashScope/                  macOS application UI and platform services
Sources/FlashScopeCore/      Platform-independent diagnostics/benchmark core
Tests/                       Core unit tests
FlashScopeIntegrationTests/  macOS integration tests
FlashScopeUITests/           UI tests
Scripts/                     Build/distribution tools
FlashScope.xcodeproj/        Xcode project
```

## Build from source

Clone the repository:

```bash
git clone https://github.com/fmniloyuk/Flash-Drive-Health-Checker-MAC-OS.git
cd Flash-Drive-Health-Checker-MAC-OS
```

Run the Xcode test suite:

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

Build the Debug app:

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
```

Run it:

```bash
open .artifacts/DerivedData/Build/Products/Debug/FlashScope.app
```

## Simulation mode

Debug builds include deterministic fixtures so diagnostic behavior can be tested without touching a real USB drive.

```bash
open .artifacts/DerivedData/Build/Products/Debug/FlashScope.app --args --simulate
```

Empty-drive simulation:

```bash
open .artifacts/DerivedData/Build/Products/Debug/FlashScope.app --args --simulate-empty
```

Fixtures cover healthy USB 2 behavior, USB 3 negotiated at USB 2 speed, poor writes, small-file overhead, integrity mismatch, repeated I/O errors, verification blocked, nearly full, read-only, and drive removal scenarios.

## Build a DMG

The repository includes `Scripts/build_dmg.sh`.

```bash
chmod +x Scripts/build_dmg.sh
./Scripts/build_dmg.sh
```

Skip tests when they were already run separately:

```bash
./Scripts/build_dmg.sh --skip-tests
```

Output:

```text
.artifacts/dist/FlashScope.app
.artifacts/dist/FlashScope.dmg
```

## Developer ID signing

Unsigned builds are useful for local development. Public distribution should use a real Apple Developer ID identity.

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
BUNDLE_ID='com.yourcompany.FlashScope' \
./Scripts/build_dmg.sh --sign
```

The script signs nested code first, signs the app with the hardened runtime, verifies the signature, packages the DMG, and signs the DMG.

## Apple notarization

Create a `notarytool` keychain profile with your own Apple Developer credentials, then run:

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
BUNDLE_ID='com.yourcompany.FlashScope' \
NOTARY_PROFILE='flashscope-notary' \
./Scripts/build_dmg.sh --sign --notarize
```

The build script never invents or stores signing identities or Apple credentials.

## GitHub Actions and releases

The repository includes a macOS CI/release workflow under `.github/workflows/macos-release.yml`.

For pushes and pull requests it:

1. Checks out the repository on a macOS runner
2. Displays the selected macOS/Xcode/Swift versions
3. Runs the Xcode test suite
4. Builds the Release application
5. Packages `FlashScope.dmg`
6. Generates a SHA-256 checksum
7. Uploads the DMG and checksum as workflow artifacts

To publish a GitHub Release, push a tag beginning with `v`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow creates or updates the matching GitHub Release and attaches:

- `FlashScope.dmg`
- `FlashScope.dmg.sha256`

The default CI release is unsigned unless real Developer ID/notarization credentials are deliberately configured as repository secrets.

## Privacy

FlashScope diagnostics run locally. Diagnostic reports can redact identifying details such as device serial numbers and user-specific filesystem paths.

No cloud service is required to inspect or benchmark a USB drive.

## Safety philosophy

**Observe first. Measure safely. Explain the evidence. Offer a safe next step. Never perform destructive remediation automatically.**

Formatting, repartitioning, destructive repair, or deleting user files remain outside FlashScope's automatic diagnostic workflow.

## Disclaimer

FlashScope is a diagnostic utility, not a substitute for backups. Storage devices can fail without warning. If FlashScope reports integrity failures, repeated I/O errors, or other critical evidence, back up important data immediately.
