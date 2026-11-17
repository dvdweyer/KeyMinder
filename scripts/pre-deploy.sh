#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Preparation for a stable release. Kept for its name; dev (`dev help`, configured by .devops)
# does each step, and the release checks of `dev release` verify them:
#
#   translations         dev localize --fill     asks before it calls the API; dev strings check
#                                                lists what is missing
#   website version      dev web render          the download links, the button and the page's
#                                                structured data follow the project version
#   "What's new"         CHANGELOG.md            the stable release notes come from it (dev
#                                                changelog --write drafts the entries)
#   cask                 dev release             writes the version and the DMG's SHA-256
#   tag                  the commit hooks        tag every app-code commit (dev hooks status)
#   commit, push         yours                   git push --follow-tags
#
# This script runs the two that only change files, and then the checks. It commits and pushes
# nothing.
#
#   --skip-translations   don't offer to fill missing translations
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v dev >/dev/null; then
    echo "error: dev isn't on PATH; it prepares the releases now." >&2
    exit 1
fi

SKIP_TRANSLATIONS=false
for arg in "$@"; do
    case "$arg" in
        --skip-translations) SKIP_TRANSLATIONS=true ;;
        --no-push) ;; # nothing is pushed any more
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$SKIP_TRANSLATIONS" == false ]]; then
    dev localize --fill || true
fi
dev web render
echo ""
echo "Review and commit the changes, push, then: dev release -n"
dev preflight --quick --release || true
