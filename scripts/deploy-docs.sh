#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copies Documentation/Website/ to the local website and rsyncs to the server.
# Use this for HTML-only updates that don't need a new binary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_DIR="$HOME/Public/Sites/donald.van-de-weyer.net/keyminder"
KEYMINDER_SITE_DIR="$HOME/Public/Sites/keyminder.app"
DEPLOY_SH="$HOME/Public/Sites/deploy.sh"

mkdir -p "$SITE_DIR" "$KEYMINDER_SITE_DIR"
cp "$REPO_DIR/Documentation/Website/keyminder.html" "$SITE_DIR/index.html"
cp "$REPO_DIR/Documentation/Website/keyminder.html" "$KEYMINDER_SITE_DIR/index.html"
for f in "$REPO_DIR/Documentation/Website/"*.png; do
    [[ -e "$f" ]] && cp "$f" "$SITE_DIR/" && cp "$f" "$KEYMINDER_SITE_DIR/"
done
for f in sitemap.xml robots.txt; do
    [[ -e "$REPO_DIR/Documentation/Website/$f" ]] && cp "$REPO_DIR/Documentation/Website/$f" "$SITE_DIR/" && cp "$REPO_DIR/Documentation/Website/$f" "$KEYMINDER_SITE_DIR/"
done
for f in "$SITE_DIR/"*.zip; do
    [[ -e "$f" ]] && cp "$f" "$KEYMINDER_SITE_DIR/"
done

cd "$(dirname "$DEPLOY_SH")" && bash "$DEPLOY_SH"
echo "Docs deployed."
