#!/bin/bash
# Updates Distribution/Casks/keyminder.rb with the new version + SHA256,
# then syncs to the local tap repo clone (TAP_REPO_DIR) and pushes if set.
#
# Usage: update-tap.sh <version> <sha256>
set -euo pipefail

VERSION="${1:?usage: update-tap.sh <version> <sha256>}"
SHA256="${2:?usage: update-tap.sh <version> <sha256>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CASK_SRC="$REPO_DIR/Distribution/Casks/keyminder.rb"

sed -i '' \
    -e "s/  version \"[^\"]*\"/  version \"$VERSION\"/" \
    -e "s/  sha256 \"[^\"]*\"/  sha256 \"$SHA256\"/" \
    "$CASK_SRC"

echo "--- Updated $CASK_SRC → $VERSION"

if [[ -z "${TAP_REPO_DIR:-}" ]]; then
    echo "    (TAP_REPO_DIR not set; skipping tap push)"
    exit 0
fi

if [[ ! -d "$TAP_REPO_DIR" ]]; then
    echo "error: TAP_REPO_DIR='$TAP_REPO_DIR' does not exist." >&2
    exit 1
fi

mkdir -p "$TAP_REPO_DIR/Casks"
cp "$CASK_SRC" "$TAP_REPO_DIR/Casks/keyminder.rb"
git -C "$TAP_REPO_DIR" add Casks/keyminder.rb
git -C "$TAP_REPO_DIR" commit -m "feat: bump keyminder to $VERSION"
git -C "$TAP_REPO_DIR" push
echo "--- Pushed tap → dvdweyer/homebrew-keyminder"
