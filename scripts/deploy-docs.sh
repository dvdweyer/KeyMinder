#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Publishes Documentation/Website/ to keyminder.app, for HTML-only updates that don't need a new
# binary. Kept for its name; dev (`dev help`, configured by .devops) does the work:
#
#   scripts/deploy-docs.sh        dev web publish     check the pages, show what changed since the last
#                                                     publish, then ask before mirroring them into the
#                                                     local site copy, before committing there and
#                                                     before deploying
#   scripts/deploy-docs.sh -n     dev web publish -n  check and show what changed, publish nothing
#
# keyminder.html is published as index.html; the appcast and the downloads on the site are left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v dev >/dev/null; then
    echo "error: dev isn't on PATH; it publishes the website now." >&2
    exit 1
fi
exec dev web publish "$@"
