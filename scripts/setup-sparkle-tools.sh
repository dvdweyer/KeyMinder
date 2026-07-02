#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Downloads the Sparkle developer tools (generate_keys, generate_appcast, sign_update)
# from a pinned GitHub release and installs them to ~/.sparkle-tools/bin/.
#
# The version is pinned and the tarball is verified against a known SHA-256 before
# extraction: these tools read the Ed25519 signing key from the Keychain and produce
# the signatures every user's Sparkle install trusts, so "latest" is not acceptable.
# (The binaries inside are only ad-hoc signed, so the hash is the integrity anchor.)
#
# To upgrade: bump SPARKLE_VERSION, download the new tarball manually, compute
# `shasum -a 256` yourself, and update SPARKLE_SHA256. Keep the version in sync
# with the app's SPM dependency (KeyMinder.xcodeproj → Package.resolved).
#
# After running this, add ~/.sparkle-tools/bin to your PATH, e.g.:
#   echo 'export PATH="$HOME/.sparkle-tools/bin:$PATH"' >> ~/.zprofile
#
# Run this script once during initial Sparkle setup.
set -euo pipefail

SPARKLE_VERSION="2.9.2"
SPARKLE_SHA256="1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95"

BIN_DIR="$HOME/.sparkle-tools/bin"
TARBALL_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
TARBALL="/tmp/Sparkle-${SPARKLE_VERSION}.tar.xz"
EXTRACT_DIR="/tmp/Sparkle-${SPARKLE_VERSION}"

echo "--- Downloading Sparkle ${SPARKLE_VERSION}..."
/usr/bin/curl -fLo "${TARBALL}" "${TARBALL_URL}"

echo "--- Verifying SHA-256..."
ACTUAL_SHA256=$(shasum -a 256 "${TARBALL}" | awk '{print $1}')
if [[ "${ACTUAL_SHA256}" != "${SPARKLE_SHA256}" ]]; then
    echo "error: SHA-256 mismatch for ${TARBALL}" >&2
    echo "       expected: ${SPARKLE_SHA256}" >&2
    echo "       actual:   ${ACTUAL_SHA256}" >&2
    echo "       The download may be corrupted or tampered with. Not installing." >&2
    rm -f "${TARBALL}"
    exit 1
fi
echo "    OK (${ACTUAL_SHA256})"

echo "--- Extracting..."
rm -rf "${EXTRACT_DIR}"
mkdir -p "${EXTRACT_DIR}"
tar -xf "${TARBALL}" -C "${EXTRACT_DIR}"

echo "--- Installing tools to ${BIN_DIR}..."
mkdir -p "${BIN_DIR}"
find "${EXTRACT_DIR}/bin" -maxdepth 1 -type f -exec cp {} "${BIN_DIR}/" \;
chmod +x "${BIN_DIR}/"*

rm -rf "${TARBALL}" "${EXTRACT_DIR}"

echo ""
echo "==> Done. Sparkle ${SPARKLE_VERSION} tools installed to ${BIN_DIR}"
echo ""
echo "Next steps:"
echo "  1. Add to PATH (if not already):  export PATH=\"\$HOME/.sparkle-tools/bin:\$PATH\""
echo "  2. Generate your Ed25519 key pair: generate_keys"
echo "  3. Copy the PUBLIC key from the output into KeyMinder/Info.plist -> SUPublicEDKey"
echo "     (the private key was stored in your Keychain automatically)"
