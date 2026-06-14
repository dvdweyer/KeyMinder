#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run once to store Apple notarization credentials in the macOS keychain.
# After this, release.sh can notarize without interactive prompts.
#
# You need an app-specific password (not your regular Apple ID password).
# Create one at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

echo "Storing Apple notarization credentials under the profile name 'KeyMinder'."
echo "You will be prompted for your app-specific password."
echo ""
read -rp "Apple ID email: " APPLE_ID

xcrun notarytool store-credentials "KeyMinder" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID"
# notarytool prompts for the app-specific password interactively and stores
# everything in the keychain — no plaintext credentials are saved anywhere.

echo ""
echo "Done. Run scripts/release.sh to build and release."
