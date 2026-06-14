#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Pre-deploy preparation for KeyMinder.
#
# Run this BEFORE scripts/release.sh. It:
#   1. Translates any missing strings in Localizable.xcstrings via the Claude API
#      (requires ANTHROPIC_API_KEY in the environment or in scripts/.env)
#   2. Updates version references in Documentation/Website/keyminder.html
#   3. Updates the version string in Distribution/Casks/keyminder.rb
#   4. Commits any modified files
#   5. Verifies git tag vX.Y.Z exists (offers to create it if missing)
#   6. Pushes the branch and tags to GitHub
#
# Flags:
#   --skip-translations   Skip the translation step
#   --no-push             Do everything except the final git push (dry-run / offline)
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Flags ─────────────────────────────────────────────────────────────────────
SKIP_TRANSLATIONS=false
NO_PUSH=false

for arg in "$@"; do
    case "$arg" in
        --skip-translations) SKIP_TRANSLATIONS=true ;;
        --no-push)           NO_PUSH=true ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ── Version ───────────────────────────────────────────────────────────────────
VERSION=$(grep 'MARKETING_VERSION' \
    "$REPO_DIR/KeyMinder.xcodeproj/project.pbxproj" \
    | head -1 | sed 's/.*MARKETING_VERSION = //; s/;//; s/[[:space:]]//g')

if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.pbxproj" >&2
    exit 1
fi

echo "==> KeyMinder pre-deploy — v${VERSION}"
echo ""

# ── 1. Translations ───────────────────────────────────────────────────────────
if [[ "$SKIP_TRANSLATIONS" == true ]]; then
    echo "--- Translation step skipped (--skip-translations)."
else
    echo "--- Translating missing strings in Localizable.xcstrings…"
    python3 "$SCRIPT_DIR/translate-missing.py"
fi

# ── 2. Documentation — keyminder.html ────────────────────────────────────────
echo ""
echo "--- Updating Documentation/Website/keyminder.html…"
HTML="$REPO_DIR/Documentation/Website/keyminder.html"

PREV_VERSION=$(grep -o 'href="KeyMinder_[0-9.]*\.zip"' "$HTML" | head -1 \
    | sed 's/href="KeyMinder_//; s/\.zip"//')
if [[ -z "$PREV_VERSION" ]]; then
    echo "error: could not detect current version in keyminder.html" >&2
    exit 1
fi

if [[ "$PREV_VERSION" == "$VERSION" ]]; then
    echo "    Already at v${VERSION} — no changes needed."
else
    TODAY=$(date '+%Y-%m-%d')
    PREV_RE="${PREV_VERSION//./\\.}"

    sed -i '' \
        -e "s|KeyMinder_${PREV_RE}\\.zip|KeyMinder_${VERSION}.zip|g" \
        -e "s|\"softwareVersion\": \"${PREV_RE}\"|\"softwareVersion\": \"${VERSION}\"|" \
        -e "s|\"dateModified\": \"[0-9-]*\"|\"dateModified\": \"${TODAY}\"|" \
        -e "s|↓ Download v${PREV_RE}|↓ Download v${VERSION}|" \
        -e "s|↓ v${PREV_RE} herunterladen|↓ v${VERSION} herunterladen|" \
        "$HTML"

    echo "    Updated v${PREV_VERSION} → v${VERSION}  (dateModified: ${TODAY})."

    # Warn if there is no changelog entry for the new version yet.
    if ! grep -qF "<strong>v${VERSION}</strong>" "$HTML"; then
        echo ""
        echo "    WARNING: no changelog entry found for v${VERSION} in keyminder.html."
        echo "             Add one under the 'What's new' section before deploying."
    fi
fi

# ── 3. Homebrew cask version ─────────────────────────────────────────────────
echo ""
echo "--- Updating Distribution/Casks/keyminder.rb…"
CASK="$REPO_DIR/Distribution/Casks/keyminder.rb"
CASK_VERSION=$(grep '  version "' "$CASK" | sed 's/.*version "//; s/"//')

if [[ "$CASK_VERSION" == "$VERSION" ]]; then
    echo "    Already at v${VERSION} — no changes needed."
else
    sed -i '' "s/  version \"${CASK_VERSION//./\\.}\"/  version \"${VERSION}\"/" "$CASK"
    echo "    Updated cask version ${CASK_VERSION} → ${VERSION}."
    echo "    (SHA256 will be filled in by release.sh after the DMG is built.)"
fi

# ── 4. Commit ─────────────────────────────────────────────────────────────────
echo ""
echo "--- Staging pre-deploy changes…"
git -C "$REPO_DIR" add \
    KeyMinder/Localizable.xcstrings \
    Documentation/Website/keyminder.html \
    Distribution/Casks/keyminder.rb

if git -C "$REPO_DIR" diff --cached --quiet; then
    echo "    Nothing to commit — all files already up to date."
else
    git -C "$REPO_DIR" commit -m "chore: pre-deploy prep for v${VERSION}"
    echo "    Committed."
fi

# Warn about any remaining untracked or modified files.
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    echo ""
    echo "warning: uncommitted changes remain in the working tree:" >&2
    git -C "$REPO_DIR" status --short >&2
    echo ""
    read -rp "Continue anyway? [y/N] " _CONT
    [[ "$_CONT" == "y" || "$_CONT" == "Y" ]] || { echo "Aborted." >&2; exit 1; }
fi

# ── 5. Tag check ──────────────────────────────────────────────────────────────
echo ""
echo "--- Checking git tag v${VERSION}…"
if git -C "$REPO_DIR" tag | grep -qxF "v${VERSION}"; then
    echo "    Tag v${VERSION} exists."
else
    echo ""
    echo "warning: tag v${VERSION} does not exist." >&2
    echo ""
    read -rp "Create tag v${VERSION} now? [y/N] " _TAG
    if [[ "$_TAG" == "y" || "$_TAG" == "Y" ]]; then
        git -C "$REPO_DIR" tag "v${VERSION}"
        echo "    Tagged v${VERSION}."
    else
        echo "Aborted — tag required before releasing." >&2
        exit 1
    fi
fi

# ── 6. Push ───────────────────────────────────────────────────────────────────
if [[ "$NO_PUSH" == true ]]; then
    echo ""
    echo "--- Push skipped (--no-push)."
else
    echo ""
    echo "--- Pushing to GitHub…"
    git -C "$REPO_DIR" push
    git -C "$REPO_DIR" push --tags
    echo "    Done."
fi

echo ""
echo "==> Pre-deploy complete — v${VERSION} is ready."
if [[ "$NO_PUSH" == false ]]; then
    echo "    Run  scripts/release.sh --remote-only  to build and deploy."
fi
