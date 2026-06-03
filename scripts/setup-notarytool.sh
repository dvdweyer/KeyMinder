#!/bin/bash
# Run once to store Apple notarization credentials in the macOS keychain.
# After this, release.sh can notarize without interactive prompts.
#
# You need an app-specific password (not your regular Apple ID password).
# Create one at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.
set -euo pipefail

echo "Storing Apple notarization credentials under the profile name 'KeyMinder'."
echo "You will be prompted for your app-specific password."
echo ""
read -rp "Apple ID email: " APPLE_ID

xcrun notarytool store-credentials "KeyMinder" \
    --apple-id "$APPLE_ID" \
    --team-id "R4J8ZNC9HF"
# notarytool prompts for the app-specific password interactively and stores
# everything in the keychain — no plaintext credentials are saved anywhere.

echo ""
echo "Done. Run scripts/release.sh to build and release."
