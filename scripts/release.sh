#!/bin/bash
# Release pipeline for KeyMinder.
#
# Usage:
#   release.sh                  — interactive prompt
#   release.sh --remote-only   — Release build, notarize, rsync; no local install
#   release.sh --full-deploy    — Release build, notarize, rsync + install to /Applications
#   release.sh --local-only     — Debug build + install to /Applications only
#
# Prerequisites (full pipeline):
#   - Copy scripts/.env.example to scripts/.env and fill in TEAM_ID.
#   - Run scripts/setup-notarytool.sh once to store keychain credentials.
#   - Run scripts/setup-sparkle-tools.sh once and add ~/.sparkle-tools/bin to PATH.
#   - Xcode must be installed at /Applications/Xcode.app.
#   - The project's Release config must be signed with Developer ID Application.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Flags ─────────────────────────────────────────────────────────────────────
MODE=""

for arg in "$@"; do
    case "$arg" in
        --local-only)   MODE="local-only" ;;
        --remote-only) MODE="remote-only" ;;
        --full-deploy)  MODE="full-deploy" ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ── Interactive prompt (no flags given) ───────────────────────────────────────
if [[ -z "$MODE" ]]; then
    echo "Which pipeline would you like to run?"
    echo "  1) remote-only  — Release build, notarize, rsync (no local install)"
    echo "  2) local-only    — Debug build, install to /Applications"
    echo "  3) full-deploy   — Release build, notarize, rsync + install to /Applications"
    echo ""
    read -rp "Choice [1/2/3]: " _CHOICE
    echo ""
    case "$_CHOICE" in
        1) MODE="remote-only" ;;
        2) MODE="local-only" ;;
        3) MODE="full-deploy" ;;
        *) echo "error: invalid choice '$_CHOICE'" >&2; exit 1 ;;
    esac
fi

# ── Local-only fast path ───────────────────────────────────────────────────────
if [[ "$MODE" == "local-only" ]]; then
    echo "==> KeyMinder — local Debug install"
    echo ""
    _BUILD_DIR="/tmp/KeyMinder-debug-$$"
    mkdir -p "$_BUILD_DIR"

    echo "--- Building (Debug)…"
    xcodebuild build \
        -project "$REPO_DIR/KeyMinder.xcodeproj" \
        -scheme KeyMinder \
        -configuration Debug \
        -derivedDataPath "$_BUILD_DIR" \
        -allowProvisioningUpdates

    echo ""
    echo "--- Installing to /Applications…"
    pkill -x KeyMinder 2>/dev/null || true
    while pgrep -x KeyMinder > /dev/null 2>&1; do sleep 0.1; done
    rm -rf /Applications/KeyMinder.app
    cp -R "$_BUILD_DIR/Build/Products/Debug/KeyMinder.app" /Applications/
    xattr -cr /Applications/KeyMinder.app
    rm -rf "$_BUILD_DIR"

    echo ""
    echo "==> Done — KeyMinder (Debug) installed to /Applications."
    exit 0
fi

SITE_DIR="$HOME/Public/Sites/donald.van-de-weyer.net/keyminder"
KEYMINDER_SITE_DIR="$HOME/Public/Sites/keyminder.app"
DEPLOY_SH="$HOME/Public/Sites/deploy.sh"
NOTARYTOOL_PROFILE="KeyMinder"
BUILD_DIR="/tmp/KeyMinder-release-$$"

# ── Config ────────────────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: $ENV_FILE not found. Copy scripts/.env.example to scripts/.env and fill in TEAM_ID." >&2
    exit 1
fi
# shellcheck source=.env
source "$ENV_FILE"

if [[ -z "${TEAM_ID:-}" ]]; then
    echo "error: TEAM_ID is not set in scripts/.env" >&2
    exit 1
fi

# ── Version ───────────────────────────────────────────────────────────────────
VERSION=$(grep 'MARKETING_VERSION' \
    "$REPO_DIR/KeyMinder.xcodeproj/project.pbxproj" \
    | head -1 | sed 's/.*MARKETING_VERSION = //; s/;//; s/[[:space:]]//g')

if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.pbxproj" >&2
    exit 1
fi

# ── QC: webpage must reference the same version ───────────────────────────────
HTML="$REPO_DIR/Documentation/keyminder.html"
HTML_VERSION=$(grep -o 'href="KeyMinder_[0-9.]*\.zip"' "$HTML" | head -1 \
    | sed 's/href="KeyMinder_//; s/\.zip"//')
if [[ "$HTML_VERSION" != "$VERSION" ]]; then
    echo "error: keyminder.html download link points to v${HTML_VERSION} but project is v${VERSION}" >&2
    echo "       Update the href, button text, install step, and changelog in Documentation/keyminder.html" >&2
    exit 1
fi

ARCHIVE="$BUILD_DIR/KeyMinder.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/KeyMinder.app"
ZIP="$BUILD_DIR/KeyMinder_${VERSION}.zip"

echo "==> KeyMinder $VERSION"
echo ""

# ── Build ─────────────────────────────────────────────────────────────────────
mkdir -p "$BUILD_DIR"

# Generate ExportOptions.plist with team ID from .env (never stored in the repo).
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo "--- Archiving…"
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
    -exportOptionsPlist "$EXPORT_OPTIONS" \
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

# ── Sparkle appcast ───────────────────────────────────────────────────────────
echo ""
echo "--- Updating Sparkle appcast…"
# generate_appcast must be on PATH. Install from Sparkle's GitHub release tarball:
#   curl -Lo /tmp/sparkle.tar.xz \
#     https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.x.y.tar.xz
#   tar -xf /tmp/sparkle.tar.xz -C ~/.sparkle-tools --strip-components=1 bin
# Then add ~/.sparkle-tools/bin to your PATH (or symlink into /usr/local/bin).
GENERATE_APPCAST=$(command -v generate_appcast 2>/dev/null || true)
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "error: generate_appcast not found in PATH." >&2
    echo "       Download Sparkle tools from https://github.com/sparkle-project/Sparkle/releases" >&2
    echo "       and add their bin/ directory to your PATH." >&2
    exit 1
fi
APPCAST="$REPO_DIR/Distribution/appcast.xml"
"$GENERATE_APPCAST" "$BUILD_DIR" \
    --download-url-prefix "https://keyminder.app/" \
    --maximum-versions 10 \
    -o "$APPCAST"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo ""
echo "--- Copying to website…"
mkdir -p "$SITE_DIR" "$KEYMINDER_SITE_DIR"
cp "$ZIP" "$SITE_DIR/"
cp "$ZIP" "$KEYMINDER_SITE_DIR/"
cp "$APPCAST" "$SITE_DIR/"
cp "$APPCAST" "$KEYMINDER_SITE_DIR/"
cp "$REPO_DIR/Documentation/keyminder.html" "$SITE_DIR/index.html"
cp "$REPO_DIR/Documentation/keyminder.html" "$KEYMINDER_SITE_DIR/index.html"
for f in "$REPO_DIR/Documentation/"*.png; do
    [[ -e "$f" ]] && cp "$f" "$SITE_DIR/" && cp "$f" "$KEYMINDER_SITE_DIR/"
done

echo "--- Deploying via rsync…"
(cd "$(dirname "$DEPLOY_SH")" && bash "$(basename "$DEPLOY_SH")")

# ── Local install (full-deploy only) ─────────────────────────────────────────
if [[ "$MODE" == "full-deploy" ]]; then
    echo ""
    echo "--- Installing to /Applications…"
    pkill -x KeyMinder 2>/dev/null || true
    while pgrep -x KeyMinder > /dev/null 2>&1; do sleep 0.1; done
    rm -rf /Applications/KeyMinder.app
    cp -R "$APP" /Applications/
    xattr -cr /Applications/KeyMinder.app
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
echo "==> Done — KeyMinder $VERSION is live."
