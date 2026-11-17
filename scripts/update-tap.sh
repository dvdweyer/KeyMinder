#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Updates Distribution/Casks/keyminder.rb and the Homebrew tap. Kept for its name;
# `dev cask update` does the work: version and sha256 in the cask, then, with TAP_REPO_DIR in
# the private .env, the commit in the tap clone and its push, each after a question. A stable
# release (`dev release`) does this on its own.
#
# Usage: update-tap.sh [-n] <version> <sha256>
set -euo pipefail
cd "$(dirname "$0")/.."
command -v dev >/dev/null || { echo "error: dev isn't on PATH; it updates the cask now." >&2; exit 1; }
exec dev cask update "$@"
