# Building FlashScope.app and FlashScope.dmg

Run these commands on a Mac with Xcode installed. The project targets macOS 14 or newer.

## 1. Local unsigned DMG

```bash
cd FlashScope
./Scripts/build_dmg.sh
```

The script runs the Xcode tests first, builds a Release app, and creates:

- `.artifacts/dist/FlashScope.app`
- `.artifacts/dist/FlashScope.dmg`

For a faster packaging run after tests have already passed:

```bash
./Scripts/build_dmg.sh --skip-tests
```

The default bundle identifier is the project placeholder `com.example.FlashScope`. Override it before distribution.

## 2. Developer ID signed DMG

First make sure the real **Developer ID Application** certificate is installed in your login Keychain. Then run:

```bash
SIGN_IDENTITY='Developer ID Application: Your Company Name (TEAMID)' \
BUNDLE_ID='com.yourcompany.FlashScope' \
./Scripts/build_dmg.sh --sign
```

The script builds unsigned first and then signs nested frameworks and the application from the inside out with hardened runtime enabled. It does not use a fake identity and does not persist credentials.

## 3. Signed and notarized DMG

Create a notarytool Keychain profile once:

```bash
xcrun notarytool store-credentials flashscope-notary \
  --apple-id 'your-apple-id@example.com' \
  --team-id 'TEAMID' \
  --password 'APP-SPECIFIC-PASSWORD'
```

Then build, sign, submit, wait for notarization, and staple the ticket:

```bash
SIGN_IDENTITY='Developer ID Application: Your Company Name (TEAMID)' \
BUNDLE_ID='com.yourcompany.FlashScope' \
NOTARY_PROFILE='flashscope-notary' \
./Scripts/build_dmg.sh --sign --notarize
```

The password is stored by `notarytool` in the macOS Keychain, not in the FlashScope repository.

## Options

```text
--skip-tests    Skip xcodebuild test
--sign          Sign with SIGN_IDENTITY
--notarize      Notarize and staple; requires --sign and NOTARY_PROFILE
--no-clean      Reuse DerivedData where possible
--help          Display complete usage
```

## Important distribution notes

- Replace `com.example.FlashScope` with a bundle identifier owned by your Apple Developer team.
- Do not commit Apple IDs, app-specific passwords, API private keys, or notarization credentials.
- The current advanced raw-read capability is deliberately disabled; the standard FlashScope build does not install a privileged helper.
- The script never formats, repairs, repartitions, or otherwise modifies USB drives. It only builds/packages the application.
