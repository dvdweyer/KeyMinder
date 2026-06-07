#!/bin/bash
# Downloads the Sparkle developer tools (generate_keys, generate_appcast, sign_update)
# from the latest GitHub release and installs them to ~/.sparkle-tools/bin/.
#
# After running this, add ~/.sparkle-tools/bin to your PATH, e.g.:
#   echo 'export PATH="$HOME/.sparkle-tools/bin:$PATH"' >> ~/.zprofile
#
# Run this script once during initial Sparkle setup.
set -euo pipefail

BIN_DIR="$HOME/.sparkle-tools/bin"

echo "--- Fetching latest Sparkle release metadata..."
RELEASE_JSON=$(/usr/bin/curl -fsSL "https://api.github.com/repos/sparkle-project/Sparkle/releases/latest")

LATEST=$(echo "${RELEASE_JSON}" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
echo "    Latest: ${LATEST}"

TARBALL_URL=$(echo "${RELEASE_JSON}" \
    | grep '"browser_download_url"' \
    | grep '\.tar\.xz"' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

if [[ -z "${TARBALL_URL}" ]]; then
    echo "error: could not find a .tar.xz asset in the latest release." >&2
    echo "       Check https://github.com/sparkle-project/Sparkle/releases for the correct filename." >&2
    exit 1
fi
echo "    Asset: ${TARBALL_URL}"

TARBALL="/tmp/Sparkle-${LATEST}.tar.xz"
EXTRACT_DIR="/tmp/Sparkle-${LATEST}"

echo "--- Downloading..."
/usr/bin/curl -fLo "${TARBALL}" "${TARBALL_URL}"

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
echo "==> Done. Sparkle tools installed to ${BIN_DIR}"
echo ""
echo "Next steps:"
echo "  1. Add to PATH (if not already):  export PATH=\"\$HOME/.sparkle-tools/bin:\$PATH\""
echo "  2. Generate your Ed25519 key pair: generate_keys"
echo "  3. Copy the PUBLIC key from the output into KeyMinder/Info.plist -> SUPublicEDKey"
echo "     (the private key was stored in your Keychain automatically)"
