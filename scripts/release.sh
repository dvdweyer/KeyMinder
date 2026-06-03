#!/bin/bash
# Full release pipeline: archive → sign (Developer ID) → notarize → staple → zip
# → copy to local website → deploy via rsync.
#
# Prerequisites:
#   - Run scripts/setup-notarytool.sh once to store keychain credentials.
#   - Xcode must be installed at /Applications/Xcode.app.
#   - The project's Release config must be signed with Developer ID Application.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_DIR="$HOME/Public/Sites/donald.van-de-weyer.net/keyminder"
DEPLOY_SH="$HOME/Public/Sites/deploy.sh"
NOTARYTOOL_PROFILE="KeyMinder"
BUILD_DIR="/tmp/KeyMinder-release-$$"

# ── Version ──────────────────────────────────────────────────────────────────
VERSION=$(grep 'MARKETING_VERSION' \
    "$REPO_DIR/KeyMinder.xcodeproj/project.pbxproj" \
    | head -1 | sed 's/.*MARKETING_VERSION = //; s/;//; s/[[:space:]]//g')

if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.pbxproj" >&2
    exit 1
fi

ARCHIVE="$BUILD_DIR/KeyMinder.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/KeyMinder.app"
ZIP="$BUILD_DIR/KeyMinder_${VERSION}.zip"
SITE_ZIP="$SITE_DIR/KeyMinder_${VERSION}.zip"

echo "==> KeyMinder $VERSION"
echo ""

# ── Build ─────────────────────────────────────────────────────────────────────
echo "--- Archiving…"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
    -project "$REPO_DIR/KeyMinder.xcodeproj" \
    -scheme KeyMinder \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates

echo ""
echo "--- Exporting (Developer ID)…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates

# ── Notarize ──────────────────────────────────────────────────────────────────
echo ""
echo "--- Zipping for notarization…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "--- Notarizing (this may take a minute)…"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

echo "--- Stapling…"
xcrun stapler staple "$APP"

echo "--- Re-zipping stapled app…"
rm "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo ""
echo "--- Copying to website…"
mkdir -p "$SITE_DIR"
cp "$ZIP" "$SITE_DIR/"
cp "$REPO_DIR/Documentation/keyminder.html" "$SITE_DIR/index.html"
# Copy any PNG assets (screenshots etc.)
for f in "$REPO_DIR/Documentation/"*.png; do
    [[ -e "$f" ]] && cp "$f" "$SITE_DIR/"
done

echo "--- Deploying via rsync…"
bash "$DEPLOY_SH"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
echo "==> Done — KeyMinder $VERSION is live."
echo "    $SITE_ZIP"
