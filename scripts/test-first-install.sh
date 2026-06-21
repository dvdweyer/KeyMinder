#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Reset KeyMinder's state to simulate a first-install experience.
# Quits the app if running; does NOT relaunch it.
#
# Usage:
#   scripts/test-first-install.sh --shallow [--delete-app]
#   scripts/test-first-install.sh --deep    [--delete-app]
#   scripts/test-first-install.sh           --delete-app
#
#   --shallow      Reset first-launch flags only (onboarding wizard, tips,
#                  nudges, hotkey seed, ignore-list seed).  User settings
#                  such as double-tap, appearance, popup content toggles,
#                  and favourites are preserved.
#   --deep         Wipe ALL preferences, disable iCloud settings sync and clear
#                  the local KVS mirror, and reset Accessibility + Input
#                  Monitoring grants, fully mimicking a fresh install.
#   --delete-app   Also delete /Applications/KeyMinder.app.
#
# Flags can be combined, e.g.: --deep --delete-app
#
# Note: Permission resets (--deep) call tccutil for the app's bundle ID only;
# no sudo required on macOS 14+.

set -euo pipefail

BUNDLE_ID="org.afaik.KeyMinder"
APP_PATH="/Applications/KeyMinder.app"

do_shallow=false
do_deep=false
do_delete_app=false

if [[ $# -eq 0 ]]; then
    echo "Reset KeyMinder to a first-install state."
    echo ""
    echo "Usage:"
    echo "  $0 --shallow [--delete-app]"
    echo "  $0 --deep    [--delete-app]"
    echo "  $0           --delete-app"
    echo ""
    echo "  --shallow      Reset first-launch flags only (onboarding wizard, tips,"
    echo "                 nudges, hotkey seed, ignore-list seed). User settings are"
    echo "                 preserved (double-tap, appearance, popup toggles, favourites)."
    echo "  --deep         Wipe ALL preferences, disable iCloud settings sync (and"
    echo "                 clear the local KVS mirror), and reset Accessibility +"
    echo "                 Input Monitoring grants (full fresh-install simulation)."
    echo "  --delete-app   Also delete ${APP_PATH}."
    echo ""
    echo "Flags can be combined, e.g.: --deep --delete-app"
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --shallow)    do_shallow=true ;;
        --deep)       do_deep=true ;;
        --delete-app) do_delete_app=true ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Run $0 without arguments to see usage." >&2
            exit 1
            ;;
    esac
done

# Quit the app if it is currently running.
if pgrep -x "KeyMinder" > /dev/null 2>&1; then
    echo "==> Quitting KeyMinder…"
    pkill -x "KeyMinder" 2>/dev/null || true
    sleep 0.6
fi

if $do_deep; then
    echo "==> Deep reset: deleting all preferences for ${BUNDLE_ID}…"
    defaults delete "$BUNDLE_ID" 2>/dev/null || true

    echo "==> Resetting Accessibility permission…"
    if tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null; then
        echo "    Accessibility reset."
    else
        echo "    tccutil failed (try with sudo, or reset manually via System Settings → Privacy & Security → Accessibility)."
    fi

    # Input Monitoring (kTCCServiceListenEvent) covers NSEvent.addGlobalMonitorForEvents
    # used by the double-tap trigger; a fresh install has this ungranted too.
    echo "==> Resetting Input Monitoring permission…"
    if tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null; then
        echo "    Input Monitoring reset."
    else
        echo "    tccutil failed (try with sudo, or reset manually via System Settings → Privacy & Security → Input Monitoring)."
    fi

    # iCloud settings sync (SettingsSync → NSUbiquitousKeyValueStore).
    # The domain delete above already removed iCloudSyncEnabled (so sync stays
    # OFF, matching a fresh install where the toggle defaults to off), but the
    # local KVS mirror in ~/Library/SyncedPreferences still holds the curated
    # settings synced from this and other Macs. Remove it so a fresh-install
    # simulation cannot repopulate settings from stale cloud data, and write the
    # toggle explicitly false in case a future build registers a non-false default.
    # NOTE: this only clears the LOCAL mirror; the shared iCloud KVS is left
    # intact so other Macs keep their synced settings.
    echo "==> Disabling iCloud settings sync and clearing local KVS mirror…"
    defaults write "$BUNDLE_ID" iCloudSyncEnabled -bool false 2>/dev/null || true
    rm -f "$HOME/Library/SyncedPreferences/${BUNDLE_ID}.plist" \
          "$HOME/Library/SyncedPreferences/${BUNDLE_ID}-"*.plist 2>/dev/null || true
elif $do_shallow; then
    echo "==> Resetting first-launch flags…"
    # Onboarding wizard
    defaults delete "$BUNDLE_ID" didShowOnboardingWizard     2>/dev/null || true
    defaults delete "$BUNDLE_ID" onboardingResumeStep        2>/dev/null || true
    # Popup onboarding tips (PopupFilterModel.tipIndex)
    defaults delete "$BUNDLE_ID" popupTipIndex               2>/dev/null || true
    # Growth nudges
    defaults delete "$BUNDLE_ID" popupOpenCount              2>/dev/null || true
    defaults delete "$BUNDLE_ID" didPromptGitHubStar         2>/dev/null || true
    # Hotkey — resets to factory default (⌥⌘K) on next launch
    defaults delete "$BUNDLE_ID" didSetDefaultHotkey         2>/dev/null || true
    defaults delete "$BUNDLE_ID" globalHotkey                2>/dev/null || true
    # Ignore-list state — reset so defaults (disabled, not seeded) are applied fresh
    defaults delete "$BUNDLE_ID" ignoreListEnabled           2>/dev/null || true
    defaults delete "$BUNDLE_ID" ignoreListShowWhenFiltering 2>/dev/null || true
    defaults delete "$BUNDLE_ID" ignoreList                  2>/dev/null || true
    defaults delete "$BUNDLE_ID" didSeedIgnoreList           2>/dev/null || true
    defaults delete "$BUNDLE_ID" didSeedIgnoredMenus         2>/dev/null || true
fi

if $do_delete_app; then
    if [[ -d "$APP_PATH" ]]; then
        echo "==> Deleting ${APP_PATH}…"
        rm -rf "$APP_PATH"
        echo "    Deleted."
    else
        echo "==> ${APP_PATH} not found, skipping."
    fi
fi

echo "Done."
