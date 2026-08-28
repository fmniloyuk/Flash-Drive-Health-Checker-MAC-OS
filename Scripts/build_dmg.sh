#!/bin/bash
set -euo pipefail

# FlashScope DMG builder
#
# Default behavior:
#   - builds a Release app without code signing
#   - optionally runs tests first
#   - packages FlashScope.app into a compressed DMG
#
# Optional Developer ID signing/notarization is enabled only when you supply
# your own real credentials. This script never invents or stores identities.
#
# Examples:
#   ./Scripts/build_dmg.sh
#   ./Scripts/build_dmg.sh --skip-tests
#   SIGN_IDENTITY='Developer ID Application: Example, Inc. (TEAMID1234)' \
#     BUNDLE_ID='com.example.flashscope' \
#     ./Scripts/build_dmg.sh --sign
#   SIGN_IDENTITY='Developer ID Application: Example, Inc. (TEAMID1234)' \
#     BUNDLE_ID='com.example.flashscope' \
#     NOTARY_PROFILE='flashscope-notary' \
#     ./Scripts/build_dmg.sh --sign --notarize
#
# Before using --notarize, create a notarytool keychain profile yourself, e.g.:
#   xcrun notarytool store-credentials flashscope-notary \
#     --apple-id 'you@example.com' --team-id 'TEAMID1234' --password 'app-specific-password'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/FlashScope.xcodeproj"
SCHEME="${SCHEME:-FlashScope}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="${BUNDLE_ID:-com.example.FlashScope}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ENTITLEMENTS="${ENTITLEMENTS:-$PROJECT_ROOT/FlashScope/Resources/FlashScope.entitlements}"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/.artifacts}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$BUILD_ROOT/dist"
STAGING_DIR="$BUILD_ROOT/dmg-staging"
APP_NAME="${APP_NAME:-FlashScope}"
DMG_NAME="${DMG_NAME:-FlashScope.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
RUN_TESTS=1
DO_SIGN=0
DO_NOTARIZE=0
CLEAN=1

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --skip-tests    Skip xcodebuild test before the Release build.
  --sign          Sign nested code and the app with SIGN_IDENTITY.
  --notarize      Submit the signed DMG with notarytool and staple it.
                  Requires --sign and NOTARY_PROFILE.
  --no-clean      Reuse existing DerivedData where possible.
  -h, --help      Show this help.

Environment variables:
  SCHEME             Xcode scheme (default: FlashScope)
  CONFIGURATION      Build configuration (default: Release)
  BUNDLE_ID          Bundle identifier (default: com.example.FlashScope)
  SIGN_IDENTITY      Real "Developer ID Application" identity for --sign
  NOTARY_PROFILE     notarytool keychain profile for --notarize
  ENTITLEMENTS       App entitlements plist path
  BUILD_ROOT         Build/output directory (default: .artifacts)
  DMG_NAME           Output filename (default: FlashScope.dmg)

Outputs:
  $DIST_DIR/$APP_NAME.app
  $DMG_PATH
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests) RUN_TESTS=0 ;;
    --sign) DO_SIGN=1 ;;
    --notarize) DO_NOTARIZE=1 ;;
    --no-clean) CLEAN=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "DMG creation requires macOS."
require_command xcodebuild
require_command hdiutil
require_command ditto
require_command codesign
require_command xcrun

[[ -d "$PROJECT_PATH" ]] || fail "Xcode project not found: $PROJECT_PATH"
[[ -f "$ENTITLEMENTS" ]] || fail "Entitlements file not found: $ENTITLEMENTS"

if [[ $DO_NOTARIZE -eq 1 && $DO_SIGN -ne 1 ]]; then
  fail "--notarize requires --sign."
fi
if [[ $DO_SIGN -eq 1 && -z "$SIGN_IDENTITY" ]]; then
  fail "--sign requires SIGN_IDENTITY to be set to your real Developer ID Application identity."
fi
if [[ $DO_NOTARIZE -eq 1 && -z "$NOTARY_PROFILE" ]]; then
  fail "--notarize requires NOTARY_PROFILE to name a notarytool keychain profile."
fi

mkdir -p "$BUILD_ROOT" "$DIST_DIR"

if [[ $CLEAN -eq 1 ]]; then
  log "Cleaning previous build artifacts"
  rm -rf "$DERIVED_DATA" "$STAGING_DIR"
  rm -f "$DMG_PATH"
fi

COMMON_XCODE_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -derivedDataPath "$DERIVED_DATA"
  "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

if [[ $RUN_TESTS -eq 1 ]]; then
  log "Running FlashScope tests"
  # macOS application tests are intentionally run only on a macOS/Xcode host.
  xcodebuild \
    "${COMMON_XCODE_ARGS[@]}" \
    -configuration Debug \
    test
fi

log "Building Release app"
xcodebuild \
  "${COMMON_XCODE_ARGS[@]}" \
  -configuration "$CONFIGURATION" \
  build

[[ -d "$APP_PATH" ]] || fail "Built app was not found at: $APP_PATH"

if [[ $DO_SIGN -eq 1 ]]; then
  log "Signing nested code with Developer ID"

  # Sign inside-out. Do not use --deep for signing; it can mask incorrect
  # nested signatures and makes the signing boundary less explicit.
  if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' item; do
      codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$item"
    done < <(find "$APP_PATH/Contents/Frameworks" \
      \( -name '*.framework' -o -name '*.dylib' \) -print0)
  fi

  for container in PlugIns XPCServices Helpers; do
    dir="$APP_PATH/Contents/$container"
    if [[ -d "$dir" ]]; then
      while IFS= read -r -d '' item; do
        codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$item"
      done < <(find "$dir" -mindepth 1 -maxdepth 2 \
        \( -name '*.appex' -o -name '*.xpc' -o -type f -perm -111 \) -print0)
    fi
  done

  log "Signing FlashScope.app with hardened runtime"
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"

  log "Verifying app signature"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH" || \
    echo "Note: Gatekeeper assessment may remain unaccepted until notarization is complete." >&2
else
  log "Building unsigned distribution"
  echo "The DMG will contain an unsigned app. Use --sign for Developer ID distribution." >&2
fi

log "Preparing DMG staging folder"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

log "Creating compressed DMG"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ $DO_SIGN -eq 1 ]]; then
  log "Signing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ $DO_NOTARIZE -eq 1 ]]; then
  log "Submitting DMG for Apple notarization"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  log "Final Gatekeeper assessment"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

log "Copying built app to dist"
rm -rf "$DIST_DIR/$APP_NAME.app"
ditto "$APP_PATH" "$DIST_DIR/$APP_NAME.app"

log "Build complete"
echo "App: $DIST_DIR/$APP_NAME.app"
echo "DMG: $DMG_PATH"
if [[ $DO_SIGN -eq 0 ]]; then
  echo "Signing: unsigned"
elif [[ $DO_NOTARIZE -eq 0 ]]; then
  echo "Signing: Developer ID signed, not notarized"
else
  echo "Signing: Developer ID signed and notarized"
fi
