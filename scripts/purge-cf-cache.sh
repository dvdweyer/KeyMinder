#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Purges the Cloudflare cache. Kept for its name; `dev cdn purge` does the work: the URLs given,
# else the appcast and the current zip. The credentials (CF_ZONE_ID, CF_API_TOKEN) come from the
# private .env; the token never appears on a command line. A release purges on its own.
#
# Usage: purge-cf-cache.sh [-n] [URL …]
set -euo pipefail
cd "$(dirname "$0")/.."
command -v dev >/dev/null || { echo "error: dev isn't on PATH; it purges the cache now." >&2; exit 1; }
exec dev cdn purge "$@"
