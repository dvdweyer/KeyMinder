#!/bin/bash
# Simulate a first-install experience by resetting KeyMinder's first-launch
# UserDefaults state and relaunching the app from /Applications.
#
# Usage:
#   scripts/test-first-install.sh           — resets first-launch flags only
#                                             (hotkey, double-tap, appearance, and
#                                             other settings are preserved)
#   scripts/test-first-install.sh --deep    — wipes ALL preferences for the app
#
# Note: Accessibility permission is NOT reset (use System Settings → Privacy &
# Security → Accessibility to revoke it manually if needed).

set -euo pipefail

BUNDLE_ID="org.afaik.KeyMinder"
APP_PATH="/Applications/KeyMinder.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found — build and copy the app to /Applications first." >&2
    exit 1
fi

# Quit the app if it is currently running.
if pgrep -x "KeyMinder" > /dev/null 2>&1; then
    echo "==> Quitting KeyMinder…"
    pkill -x "KeyMinder" 2>/dev/null || true
    sleep 0.6
fi

if [[ "${1:-}" == "--deep" ]]; then
    echo "==> Deep reset: deleting all preferences for ${BUNDLE_ID}..."
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
else
    echo "==> Resetting first-launch flags..."
    # didShowWelcome — controls whether Settings opens on launch
    defaults delete "$BUNDLE_ID" didShowWelcome           2>/dev/null || true
    # didSetDefaultHotkey + globalHotkey — triggers re-seeding of ⌥⌘K
    defaults delete "$BUNDLE_ID" didSetDefaultHotkey      2>/dev/null || true
    defaults delete "$BUNDLE_ID" globalHotkey             2>/dev/null || true
    # Ignore-list state — reset so defaults (disabled, not seeded) are applied fresh
    defaults delete "$BUNDLE_ID" ignoreListEnabled        2>/dev/null || true
    defaults delete "$BUNDLE_ID" ignoreListShowWhenFiltering 2>/dev/null || true
    defaults delete "$BUNDLE_ID" ignoreList               2>/dev/null || true
    defaults delete "$BUNDLE_ID" didSeedIgnoreList        2>/dev/null || true
fi

echo "==> Launching $APP_PATH…"
open "$APP_PATH"
echo "Done."
