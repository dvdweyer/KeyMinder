#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs the Sparkle developer tools (generate_keys, generate_appcast, sign_update) into
# ~/.sparkle-tools/bin/. Kept for its name; `dev setup sparkle` does the work.
#
# The version is pinned and the tarball is verified against a known SHA-256 before extraction:
# these tools read the Ed25519 signing key from the Keychain and produce the signatures every
# user's Sparkle install trusts, so "latest" is not acceptable. (The binaries inside are only
# ad-hoc signed, so the hash is the integrity anchor.)
#
# To upgrade: download the new tarball yourself, compute `shasum -a 256`, and set
# SPARKLE_VERSION and SPARKLE_SHA256 in .devops. Keep the version in step with the Sparkle
# package the app resolves (`dev doctor` compares the three).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v dev >/dev/null || { echo "error: dev isn't on PATH; it installs the Sparkle tools now." >&2; exit 1; }
exec dev setup sparkle "$@"
