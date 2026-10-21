#!/bin/zsh
# Re-sign and reinstall Turbo Health on Armin's iPhone before the free Apple
# ID's 7-day signature runs out (docs/MAC_SETUP.md › "Install on the iPhone").
#
# Run by the launchd agent ~/Library/LaunchAgents/com.armin.turbohealth.renew.plist
# every few hours; it does real work only when the last install is older than
# RENEW_AFTER_DAYS and the phone is reachable (cable or same Wi-Fi with
# "Connect via network" on in Xcode). Builds the current origin/main in its own
# worktree, so the checkout Armin or Claude work in is never touched.
#
# Usage: tool/renew_iphone.sh [--force]
set -euo pipefail

UDID="${TURBO_UDID:-00008120-0009588236D8C01E}"
BUNDLE="com.example.openstrapEdge.PY4FST339R"
REPO="${TURBO_REPO:-$HOME/Developer/edge}"
WORKTREE="$HOME/Developer/edge-renew"
STATE="$HOME/Library/Application Support/TurboHealthRenew"
LOG="$HOME/Library/Logs/turbohealth-renew.log"
RENEW_AFTER_DAYS=4

export PATH="$HOME/development/flutter/bin:$HOME/.pub-cache/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8

mkdir -p "$STATE"
log() { print -r -- "$(date '+%F %T') $*" >> "$LOG"; }
notify() { osascript -e "display notification \"$1\" with title \"Turbo Health\"" 2>/dev/null || true; }

# Due?
if [[ "${1:-}" != "--force" && -f "$STATE/last_install" ]]; then
  last=$(<"$STATE/last_install")
  age_days=$(( ($(date +%s) - last) / 86400 ))
  if (( age_days < RENEW_AFTER_DAYS )); then
    exit 0
  fi
fi

# Reachable? (cable, or Wi-Fi with "Connect via network")
if ! xcrun devicectl list devices 2>/dev/null | grep "$UDID" | grep -q "connected"; then
  log "due, but the iPhone is not reachable; next try later"
  exit 0
fi

log "renewing: building origin/main"
git -C "$REPO" fetch -q origin
if [[ ! -d "$WORKTREE" ]]; then
  git -C "$REPO" worktree add -q --detach "$WORKTREE" origin/main
fi
git -C "$WORKTREE" checkout -q --detach origin/main
git -C "$WORKTREE" reset -q --hard origin/main
# Local-only files: the .env and the signing config never live in git.
cp "$REPO/.env" "$WORKTREE/.env"
cp "$REPO/ios/Config/Signing.xcconfig" "$WORKTREE/ios/Config/Signing.xcconfig"

cd "$WORKTREE"
if ! flutter build ios --release --dart-define-from-file=.env >> "$LOG" 2>&1; then
  log "build FAILED"
  notify "Erneuerung fehlgeschlagen (Build). Details: ~/Library/Logs/turbohealth-renew.log"
  exit 1
fi
git checkout -q -- pubspec.lock 2>/dev/null || true

# Never ship a build without HealthKit (AltStore lesson).
if ! codesign -d --entitlements :- build/ios/iphoneos/Runner.app 2>/dev/null | grep -q healthkit; then
  log "build has no HealthKit entitlement; not installing"
  notify "Erneuerung abgebrochen: Build ohne HealthKit."
  exit 1
fi

if ! xcrun devicectl device install app --device "$UDID" build/ios/iphoneos/Runner.app >> "$LOG" 2>&1; then
  log "install FAILED (phone locked or out of reach?); next try later"
  exit 1
fi

# Exactly one Turbo Health, the same bundle: the band must keep one owner.
count=$(xcrun devicectl device info apps --device "$UDID" 2>/dev/null | grep -c "$BUNDLE" || true)
if [[ "$count" != "1" ]]; then
  log "WARNING: found $count installs of $BUNDLE"
fi

date +%s > "$STATE/last_install"
log "renewed ($(git rev-parse --short HEAD)); valid for 7 days"
notify "App neu signiert, wieder 7 Tage gültig ($(git rev-parse --short HEAD))."
