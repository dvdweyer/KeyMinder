#!/bin/bash
# Reset KeyMinder's state to simulate a first-install experience.
# Quits the app if running but does NOT relaunch it.
#
# Usage:
#   scripts/test-first-install.sh           — resets first-launch flags only;
#                                             user settings (double-tap, appearance,
#                                             popup content toggles) are preserved
#   scripts/test-first-install.sh --deep    — wipes ALL preferences and resets
#                                             Accessibility + Input Monitoring grants,
#                                             fully mimicking a fresh install
#
# Note: Permission resets (--deep) call tccutil for the app's bundle ID only;
# no sudo required on macOS 14+.

set -euo pipefail

BUNDLE_ID="org.afaik.KeyMinder"

# Quit the app if it is currently running.
if pgrep -x "KeyMinder" > /dev/null 2>&1; then
    echo "==> Quitting KeyMinder…"
    pkill -x "KeyMinder" 2>/dev/null || true
    sleep 0.6
fi

if [[ "${1:-}" == "--deep" ]]; then
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
else
    echo "==> Resetting first-launch flags…"
    # Onboarding wizard
    defaults delete "$BUNDLE_ID" didShowOnboardingWizard     2>/dev/null || true
    defaults delete "$BUNDLE_ID" onboardingResumeStep        2>/dev/null || true
    # Popup onboarding tips (PopupFilterModel.tipIndex)
    defaults delete "$BUNDLE_ID" popupTipIndex               2>/dev/null || true
    # Hotkey — resets to factory default (⌥⌘K) on next launch
    defaults delete "$BUNDLE_ID" didSetDefaultHotkey         2>/dev/null || true
    defaults delete "$BUNDLE_ID" globalHotkey                2>/dev/null || true
    # Ignore-list state — reset so defaults (disabled, not seeded) are applied fresh
    defaults delete "$BUNDLE_ID" ignoreListEnabled           2>/dev/null || true
    defaults delete "$BUNDLE_ID" ignoreListShowWhenFiltering 2>/dev/null || true
    defaults delete "$BUNDLE_ID" ignoreList                  2>/dev/null || true
    defaults delete "$BUNDLE_ID" didSeedIgnoreList           2>/dev/null || true
fi

echo "Done."
