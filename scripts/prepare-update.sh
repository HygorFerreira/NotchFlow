#!/usr/bin/env bash
# Prepare the signed update assets; nothing is published by this script.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?Usage: bash scripts/prepare-update.sh /path/to/NotchFlow.app}"
TOOLS="${NOTCHFLOW_SPARKLE_BIN:-build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="${NOTCHFLOW_SPARKLE_ACCOUNT:-NotchFlow}"
for tool in generate_keys generate_appcast sign_update; do
  [[ -x "$TOOLS/$tool" ]] || { echo "Missing Sparkle tool: $TOOLS/$tool" >&2; exit 1; }
done
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || { echo "Invalid release version/build" >&2; exit 1; }
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
KEYCHAIN_PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
[[ "$PUBLIC_KEY" == "$KEYCHAIN_PUBLIC_KEY" ]] || { echo "Signing key does not match this app" >&2; exit 1; }
OUT="build/updates/v$VERSION"
mkdir -p "$OUT"
# Reuse only an unchanged output. Never silently replace an already prepared
# version with different bytes; published version numbers must be immutable.
ZIP="$OUT/NotchFlow-$VERSION.zip"
[[ ! -e "$ZIP" ]] || { echo "Already prepared: $ZIP. Use a new version/build or a fresh output directory." >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
if [[ -f "releases/$VERSION.md" ]]; then cp "releases/$VERSION.md" "$OUT/NotchFlow-$VERSION.md"; fi
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/HygorFerreira/NotchFlow/releases/download/v$VERSION/" \
  --link "https://github.com/HygorFerreira/NotchFlow/releases/tag/v$VERSION" "$OUT"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$OUT/appcast.xml"
python3 scripts/validate-appcast.py "$APP" "$OUT/appcast.xml" "$ZIP"
bash scripts/test-update-archive.sh "$APP" "$OUT/appcast.xml" "$ZIP"
(cd "$OUT" && shasum -a 256 "NotchFlow-$VERSION.zip" appcast.xml > SHA256SUMS)
echo "Signed update ready: $OUT (build $BUILD)"
