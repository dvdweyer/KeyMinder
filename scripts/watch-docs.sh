#!/bin/bash
# Watches Documentation/Website/ and auto-deploys on every save.
# Run this in a terminal while editing keyminder.html.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOC_DIR="$(cd "$SCRIPT_DIR/../Documentation" && pwd)"

echo "Watching $DOC_DIR — deploying on every change. Ctrl-C to stop."
echo ""

fswatch -o \
    --exclude '\.DS_Store' \
    --exclude '.*\.swp$' \
    "$DOC_DIR" | while read -r _; do
    echo "[$(date '+%H:%M:%S')] Change detected — deploying…"
    bash "$SCRIPT_DIR/deploy-docs.sh"
done
