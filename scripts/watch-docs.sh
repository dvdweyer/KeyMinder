#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Watches Website/ while you edit: dev web watch serves a local preview of the page,
# rebuilds and re-checks it on every save. Nothing is deployed; publish with scripts/deploy-docs.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v dev >/dev/null; then
    echo "error: dev isn't on PATH; it runs the preview now." >&2
    exit 1
fi
exec dev web watch
