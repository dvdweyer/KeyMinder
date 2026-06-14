#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Purge Cloudflare cache for keyminder.app after a release.
#
# Usage:
#   purge-cf-cache.sh                    — purge appcast.xml + current version ZIP
#   purge-cf-cache.sh <url> [<url>...]   — purge specific URLs
#
# Requires CF_ZONE_ID and CF_API_TOKEN in scripts/.env (or the environment).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if credentials not already in the environment.
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "${CF_ZONE_ID:-}" || -z "${CF_API_TOKEN:-}" ]]; then
    echo "error: CF_ZONE_ID and CF_API_TOKEN must be set in scripts/.env or the environment." >&2
    exit 1
fi

# Build the list of URLs to purge.
if [[ $# -gt 0 ]]; then
    URLS=("$@")
else
    VERSION=$(grep 'MARKETING_VERSION' \
        "$REPO_DIR/KeyMinder.xcodeproj/project.pbxproj" \
        | head -1 | sed 's/.*MARKETING_VERSION = //; s/;//; s/[[:space:]]//g')
    if [[ -z "$VERSION" ]]; then
        echo "error: could not read MARKETING_VERSION from project.pbxproj" >&2
        exit 1
    fi
    URLS=(
        "https://keyminder.app/appcast.xml"
        "https://keyminder.app/KeyMinder_${VERSION}.zip"
    )
fi

# Build the JSON files array.
FILES_JSON=$(printf '"%s",' "${URLS[@]}")
FILES_JSON="[${FILES_JSON%,}]"

echo "--- Purging Cloudflare cache for ${#URLS[@]} URL(s)…"
for url in "${URLS[@]}"; do
    echo "    $url"
done

RESPONSE=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"files\": ${FILES_JSON}}")

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "    Done."
else
    echo "error: Cloudflare purge failed." >&2
    echo "$RESPONSE" >&2
    exit 1
fi
