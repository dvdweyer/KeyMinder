#!/bin/bash
# Copies Documentation/ to the local website and rsyncs to the server.
# Use this for HTML-only updates that don't need a new binary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_DIR="$HOME/Public/Sites/donald.van-de-weyer.net/keyminder"
DEPLOY_SH="$HOME/Public/Sites/deploy.sh"

mkdir -p "$SITE_DIR"
cp "$REPO_DIR/Documentation/keyminder.html" "$SITE_DIR/index.html"
for f in "$REPO_DIR/Documentation/"*.png; do
    [[ -e "$f" ]] && cp "$f" "$SITE_DIR/"
done

bash "$DEPLOY_SH"
echo "Docs deployed."
