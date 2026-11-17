#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Release pipeline for KeyMinder. Kept for its name and its modes; dev (`dev help`, configured
# by .devops) does the work:
#
#   release.sh --alpha         dev alpha                 alpha channel: notarized zip, appcast item
#   release.sh --beta          dev beta                  beta channel: the same
#   release.sh --remote-only   dev release               stable: zip, DMG, appcast, website, cask
#   release.sh --full-deploy   dev release, then         stable, and the notarized build installed
#                              dev install --released    in /Applications
#   release.sh --local-only    dev install --debug       Debug build into /Applications
#
# Add -n to see the plan without building anything.
#
# dev runs the release checks first. It asks before it sends the build to Apple's notary
# service, and again before anything is public (appcast, website copy, deploy, CDN purge). The
# Homebrew tap, the commit of the appcast and cask in this repo, and the push each ask too.
# A no at the second question leaves the notarized files in the private Releases folder and
# changes nothing else.
#
# Prerequisites: a notarytool Keychain profile (NOTARY_PROFILE in .devops;
# scripts/setup-notarytool.sh), the Sparkle tools (dev setup sparkle), Xcode in
# /Applications, and for the CDN purge and the Homebrew tap the values in the private .env
# (scripts/.env.example).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v dev >/dev/null; then
    echo "error: dev isn't on PATH; it makes the releases now." >&2
    exit 1
fi

MODE=""
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --alpha|--beta|--remote-only|--full-deploy|--local-only) MODE="${arg#--}" ;;
        -n|--dry-run|--quick) ARGS+=("$arg") ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    sed -n '3,13p' "$0"
    exit 0
fi

case "$MODE" in
    alpha)       exec dev alpha ${ARGS[@]+"${ARGS[@]}"} ;;
    beta)        exec dev beta ${ARGS[@]+"${ARGS[@]}"} ;;
    remote-only) exec dev release ${ARGS[@]+"${ARGS[@]}"} ;;
    local-only)  exec dev install --debug ;;
    full-deploy)
        dev release ${ARGS[@]+"${ARGS[@]}"}
        for arg in ${ARGS[@]+"${ARGS[@]}"}; do
            [[ "$arg" == "-n" || "$arg" == "--dry-run" ]] && exec dev install --released -n
        done
        exec dev install --released ;;
esac
