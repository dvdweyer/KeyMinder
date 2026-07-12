#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Release pipeline for KeyMinder.
#
# Usage:
#   release.sh                  — interactive prompt
#   release.sh --remote-only   — Release build, notarize, rsync; no local install
#   release.sh --full-deploy    — Release build, notarize, rsync + install to /Applications
#   release.sh --local-only     — Debug build + install to /Applications only
#   release.sh --beta           — Release build, notarize, rsync (beta channel, ZIP only)
#
# Prerequisites (full pipeline):
#   - Copy scripts/.env.example to ~/Documents/Development/.config/KeyMinder/scripts/.env and fill in TEAM_ID.
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
        --beta)         MODE="beta" ;;
        --alpha)        MODE="alpha" ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ── Interactive prompt (no flags given) ───────────────────────────────────────
if [[ -z "$MODE" ]]; then
    echo "Which pipeline would you like to run?"
    echo "  1) remote-only  — Release build, notarize, rsync (no local install)"
    echo "  2) local-only    — Debug build, install to /Applications"
    echo "  3) full-deploy   — Release build, notarize, rsync + install to /Applications"
    echo "  4) beta          — Release build, notarize, rsync (beta channel, ZIP only)"
    echo "  5) alpha         — Release build, notarize, rsync (alpha channel, ZIP only)"
    echo ""
    read -rp "Choice [1/2/3/4/5]: " _CHOICE
    echo ""
    case "$_CHOICE" in
        1) MODE="remote-only" ;;
        2) MODE="local-only" ;;
        3) MODE="full-deploy" ;;
        4) MODE="beta" ;;
        5) MODE="alpha" ;;
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
    _kw=0
    while pgrep -x KeyMinder > /dev/null 2>&1; do
        sleep 0.1; _kw=$(( _kw + 1 ))
        if (( _kw >= 50 )); then
            echo "warning: KeyMinder still running after 5 s; continuing anyway." >&2; break
        fi
    done
    rm -rf /Applications/KeyMinder.app
    cp -R "$_BUILD_DIR/Build/Products/Debug/KeyMinder.app" /Applications/
    xattr -cr /Applications/KeyMinder.app
    rm -rf "$_BUILD_DIR"

    echo ""
    echo "==> Done — KeyMinder (Debug) installed to /Applications."
    exit 0
fi

# CHANNEL is non-empty ("beta" or "alpha") for prerelease modes; empty for stable.
CHANNEL=""
[[ "$MODE" == "beta" || "$MODE" == "alpha" ]] && CHANNEL="$MODE"

SITE_DIR="$HOME/Public/Sites/app.keyminder"
DEPLOY_SH="$HOME/Public/Sites/deploy.sh"
NOTARYTOOL_PROFILE="KeyMinder"
BUILD_DIR="/tmp/KeyMinder-release-$$"
trap 'rm -rf "$BUILD_DIR"' EXIT

if [[ ! -f "$DEPLOY_SH" ]]; then
    echo "error: $DEPLOY_SH not found. Aborting before build starts." >&2
    exit 1
fi

# ── Config ────────────────────────────────────────────────────────────────────
ENV_FILE="$HOME/Documents/Development/.config/KeyMinder/scripts/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: $ENV_FILE not found. Copy scripts/.env.example to that path and fill in TEAM_ID." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${TEAM_ID:-}" ]]; then
    echo "error: TEAM_ID is not set in $ENV_FILE" >&2
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

if ! git -C "$REPO_DIR" tag | grep -qxF "v${VERSION}"; then
    echo "error: git tag v${VERSION} not found. Tag before releasing:" >&2
    echo "       git tag v${VERSION} && git push origin v${VERSION}" >&2
    exit 1
fi

# ── QC: webpage must reference the same version (stable only) ─────────────────
if [[ -z "$CHANNEL" ]]; then
    HTML="$REPO_DIR/Documentation/Website/keyminder.html"
    HTML_VERSION=$(grep -o 'href="KeyMinder_[0-9.]*\.dmg"' "$HTML" | head -1 \
        | sed 's/href="KeyMinder_//; s/\.dmg"//')
    if [[ "$HTML_VERSION" != "$VERSION" ]]; then
        echo "error: keyminder.html download link points to v${HTML_VERSION} but project is v${VERSION}" >&2
        echo "       Update the DMG href, button text, install step, and changelog in Documentation/Website/keyminder.html" >&2
        exit 1
    fi
fi

ARCHIVE="$BUILD_DIR/KeyMinder.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/KeyMinder.app"
ZIP="$BUILD_DIR/KeyMinder_${VERSION}.zip"
DMG="$BUILD_DIR/KeyMinder_${VERSION}.dmg"

if [[ -n "$CHANNEL" ]]; then
    echo "==> KeyMinder $VERSION ($CHANNEL)"
else
    echo "==> KeyMinder $VERSION"
fi
echo ""

# ── Build ─────────────────────────────────────────────────────────────────────
mkdir -p "$BUILD_DIR"

# Generate ExportOptions.plist with team ID from the external .env (never stored in the repo).
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
_ARCHIVE_EXTRA_SETTINGS=()
if [[ -n "$CHANNEL" ]]; then
    _ARCHIVE_EXTRA_SETTINGS+=(KM_RELEASE_CHANNEL="$CHANNEL")
fi
xcodebuild archive \
    -project "$REPO_DIR/KeyMinder.xcodeproj" \
    -scheme KeyMinder \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    "${_ARCHIVE_EXTRA_SETTINGS[@]+"${_ARCHIVE_EXTRA_SETTINGS[@]}"}"

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

# ── DMG (stable only) ─────────────────────────────────────────────────────────
if [[ -z "$CHANNEL" ]]; then
    echo ""
    echo "--- Creating DMG…"
    DMG_STAGING="$BUILD_DIR/dmg_staging"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create \
        -volname "KeyMinder" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        "$DMG"
    rm -rf "$DMG_STAGING"

    echo "--- Notarizing DMG…"
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        --wait

    echo "--- Stapling DMG…"
    xcrun stapler staple "$DMG"
    DMG_SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
fi

# ── Sparkle appcast ───────────────────────────────────────────────────────────
echo ""
echo "--- Updating Sparkle appcast…"
# generate_appcast must be on PATH. Install via scripts/setup-sparkle-tools.sh,
# which pins the Sparkle version and verifies the tarball SHA-256 before installing.
GENERATE_APPCAST=$(command -v generate_appcast 2>/dev/null \
    || echo "$HOME/.sparkle-tools/bin/generate_appcast")
if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "error: generate_appcast not found in PATH or ~/.sparkle-tools/bin." >&2
    echo "       Run scripts/setup-sparkle-tools.sh to install it." >&2
    exit 1
fi
APPCAST="$REPO_DIR/Distribution/appcast.xml"
APPCAST_ASSETS="$BUILD_DIR/appcast_assets"
mkdir -p "$APPCAST_ASSETS"
cp "$ZIP" "$APPCAST_ASSETS/"

# ── Release notes ─────────────────────────────────────────────────────────────
# generate_appcast auto-embeds a .html/.md/.txt file that shares the enclosure's
# basename (KeyMinder_<version>.html here) as CDATA release notes — no extra flag
# needed as long as the file has no DOCTYPE/body tags.
NOTES_FILE="$APPCAST_ASSETS/KeyMinder_${VERSION}.html"
if [[ -z "$CHANNEL" ]]; then
    # Stable: pull the "What's new" blocks from the website changelog for every
    # version newer than the last stable release already in the appcast, so a
    # multi-version jump still gets a full overview, not just the newest entry.
    LAST_STABLE=$(python3 - "$APPCAST" <<'PYEOF'
import re, sys

try:
    with open(sys.argv[1]) as f:
        xml = f.read()
except FileNotFoundError:
    sys.exit(0)

for item in re.findall(r'<item>.*?</item>', xml, re.DOTALL):
    if '<sparkle:channel>' not in item:
        m = re.search(r'<sparkle:shortVersionString>([\d.]+)</sparkle:shortVersionString>', item)
        if m:
            print(m.group(1))
            break
PYEOF
    )

    python3 - "$REPO_DIR/Documentation/Website/keyminder.html" "$LAST_STABLE" "$VERSION" "$NOTES_FILE" <<'PYEOF'
import re, sys

html_path, last_stable, version, out_path = sys.argv[1:5]

def vtuple(v):
    return tuple(int(x) for x in v.split('.'))

last_t = vtuple(last_stable) if last_stable else (0, 0, 0)
cur_t = vtuple(version)

with open(html_path) as f:
    page = f.read()

blocks = re.findall(r'<div class="changelog-entry">.*?</ul>\s*</div>', page, re.DOTALL)

selected = []
for block in blocks:
    m = re.search(r'<strong>v([\d.]+)(?:.v([\d.]+))?</strong>', block)
    if not m:
        continue
    v = m.group(2) or m.group(1)
    if last_t < vtuple(v) <= cur_t:
        selected.append(block)

if selected:
    with open(out_path, 'w') as f:
        f.write('\n'.join(selected))
PYEOF

    if [[ ! -f "$NOTES_FILE" ]]; then
        echo "warning: no changelog entry found in keyminder.html for v${VERSION}; release notes will be empty." >&2
    fi
else
    # Beta/alpha: the website isn't updated for these, so auto-generate notes
    # from git log since the previous release tag (any channel — tags are
    # shared across channels when a build is promoted without a new commit).
    PREV_TAG=$(git -C "$REPO_DIR" tag -l 'v*' --sort=-v:refname \
        | awk -v cur="v${VERSION}" 'found{print; exit} $0==cur{found=1}')

    if [[ -n "$PREV_TAG" ]]; then
        # Written to a file rather than piped via heredoc because python3 needs
        # stdin free to receive the git log output below.
        BETA_NOTES_SCRIPT="$BUILD_DIR/gen_beta_notes.py"
        cat > "$BETA_NOTES_SCRIPT" <<'PYEOF'
import html, re, sys

out_path = sys.argv[1]
labels = {"feat": "New", "fix": "Fixed", "perf": "Improved", "security": "Security", "sec": "Security"}

items = []
for line in sys.stdin:
    line = line.strip()
    m = re.match(r'(?i)^(feat|fix|perf|security|sec):\s*(.+)$', line)
    if not m:
        continue
    prefix, desc = m.group(1).lower(), m.group(2)
    desc = re.sub(r'\s*\(v[\d.]+\)\s*$', '', desc)
    items.append(f'<li><strong>{labels[prefix]}:</strong> {html.escape(desc)}</li>')

if items:
    with open(out_path, 'w') as f:
        f.write('<ul>\n' + '\n'.join(items) + '\n</ul>\n')
PYEOF
        git -C "$REPO_DIR" log "${PREV_TAG}..v${VERSION}" --no-merges --pretty=format:'%s' \
            | python3 "$BETA_NOTES_SCRIPT" "$NOTES_FILE"
    fi
fi

if [[ -n "$CHANNEL" ]]; then
    "$GENERATE_APPCAST" "$APPCAST_ASSETS" \
        --download-url-prefix "https://keyminder.app/" \
        --maximum-versions 3 \
        --channel "$CHANNEL" \
        -o "$APPCAST"
else
    "$GENERATE_APPCAST" "$APPCAST_ASSETS" \
        --download-url-prefix "https://keyminder.app/" \
        --maximum-versions 10 \
        -o "$APPCAST"
fi

# Inject sparkle:minimumAutoupdateVersion into every item that is NOT the newest.
# This creates a version floor: Sparkle will refuse to install any old enclosure
# automatically unless the installed bundle version already meets the floor,
# defending against MITM replay of genuine old signed builds.
# The newest item itself gets no floor (it IS the target).
NEW_BUILD=$(grep -m1 '<sparkle:version>' "$APPCAST" | sed 's/.*<sparkle:version>//; s/<\/sparkle:version>//')
python3 - "$APPCAST" "$NEW_BUILD" <<'PYEOF'
import sys, re

path, new_build = sys.argv[1], sys.argv[2]
with open(path) as f:
    xml = f.read()

items = list(re.finditer(r'<item>.*?</item>', xml, re.DOTALL))
if len(items) <= 1:
    sys.exit(0)

floor_tag = f'            <sparkle:minimumAutoupdateVersion>{new_build}</sparkle:minimumAutoupdateVersion>\n        '
# Process from end to preserve string positions; skip the first (newest) item.
for item in reversed(items[1:]):
    block = item.group(0)
    if 'minimumAutoupdateVersion' not in block:
        new_block = block.replace('</item>', floor_tag + '</item>')
        xml = xml[:item.start()] + new_block + xml[item.end():]

with open(path, 'w') as f:
    f.write(xml)
PYEOF

# ── Deploy ────────────────────────────────────────────────────────────────────
echo ""
echo "--- Copying to website…"
mkdir -p "$SITE_DIR"
cp "$ZIP" "$SITE_DIR/"
cp "$APPCAST" "$SITE_DIR/"
if [[ -z "$CHANNEL" ]]; then
    cp "$DMG" "$SITE_DIR/"
    cp "$REPO_DIR/Documentation/Website/keyminder.html" "$SITE_DIR/index.html"
    for f in "$REPO_DIR/Documentation/Website/"*.png "$REPO_DIR/Documentation/Website/"*.ico; do
        [[ -e "$f" ]] && cp "$f" "$SITE_DIR/"
    done
    for f in sitemap.xml robots.txt .htaccess; do
        [[ -e "$REPO_DIR/Documentation/Website/$f" ]] && cp "$REPO_DIR/Documentation/Website/$f" "$SITE_DIR/"
    done
fi

# Only stable runs recopy the ZIP/DMG for every channel (see the
# [[ -z "$CHANNEL" ]] gate above), so only prune here on stable runs too —
# otherwise a beta/alpha-only run can delete the live stable release's files
# without replacing them, leaving the website/appcast pointing at a 404.
if [[ -z "$CHANNEL" ]]; then
    echo "--- Pruning old ZIP/DMG files older than 5 days…"
    find "$SITE_DIR" \( -name "*.zip" -o -name "*.dmg" \) -mtime +5 -print -delete
fi

echo "--- Deploying via rsync…"
(cd "$(dirname "$DEPLOY_SH")" && bash "$(basename "$DEPLOY_SH")" app.keyminder)

echo ""
echo "--- Purging Cloudflare cache…"
bash "$SCRIPT_DIR/purge-cf-cache.sh" \
    || echo "warning: CF purge failed — check CF_ZONE_ID/CF_API_TOKEN in $ENV_FILE"

# ── Local install (full-deploy only) ─────────────────────────────────────────
if [[ "$MODE" == "full-deploy" ]]; then
    echo ""
    echo "--- Installing to /Applications…"
    pkill -x KeyMinder 2>/dev/null || true
    _kw=0
    while pgrep -x KeyMinder > /dev/null 2>&1; do
        sleep 0.1; _kw=$(( _kw + 1 ))
        if (( _kw >= 50 )); then
            echo "warning: KeyMinder still running after 5 s; continuing anyway." >&2; break
        fi
    done
    rm -rf /Applications/KeyMinder.app
    cp -R "$APP" /Applications/
    xattr -cr /Applications/KeyMinder.app
fi

# ── Homebrew tap (stable only) ────────────────────────────────────────────────
if [[ -z "$CHANNEL" ]]; then
    echo ""
    echo "--- Updating Homebrew cask…"
    TAP_REPO_DIR="${TAP_REPO_DIR:-$HOME/Documents/Development/.config/KeyMinder/homebrew}" bash "$SCRIPT_DIR/update-tap.sh" "$VERSION" "$DMG_SHA256"
fi

# ── Commit release artifacts back to repo ────────────────────────────────────
echo ""
echo "--- Committing release artifacts…"
if [[ -n "$CHANNEL" ]]; then
    git -C "$REPO_DIR" add Distribution/appcast.xml
    if ! git -C "$REPO_DIR" diff --cached --quiet; then
        git -C "$REPO_DIR" commit -m "chore: ${CHANNEL} appcast for v${VERSION}"
        git -C "$REPO_DIR" push
    fi
else
    git -C "$REPO_DIR" add Distribution/appcast.xml Distribution/Casks/keyminder.rb
    if ! git -C "$REPO_DIR" diff --cached --quiet; then
        git -C "$REPO_DIR" commit -m "chore: release artifacts for v${VERSION} (appcast, cask)"
        git -C "$REPO_DIR" push
    fi
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
if [[ -n "$CHANNEL" ]]; then
    echo "==> Done — KeyMinder $VERSION ($CHANNEL) is live."
else
    echo "==> Done — KeyMinder $VERSION is live."
fi
