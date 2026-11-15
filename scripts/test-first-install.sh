#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Reset KeyMinder to a first-install state. Kept for the old command; `dev reset` does the work.
# It asks once before it changes anything and never starts the app again.
#
#   --shallow      the first-run keys in .devops-reset (settings are kept)
#   --deep         all preferences, the Accessibility and Input Monitoring grants (TCC_SERVICES
#                  in .devops) and the local iCloud key-value mirror
#   --delete-app   also move /Applications/KeyMinder.app to the Trash
set -euo pipefail
if [[ $# -eq 0 ]]; then sed -n '3,9p' "$0"; exit 0; fi
command -v dev >/dev/null || { echo "error: dev isn't on PATH; it does the reset now." >&2; exit 1; }
exec dev -C "$(cd "$(dirname "$0")/.." && pwd)" reset "$@"
