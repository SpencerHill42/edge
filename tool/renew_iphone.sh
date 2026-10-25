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

# Due? The PROFILE's expiry is what counts, not the install date: on
# 2026-10-25 a renewal three days earlier had reused the cached 7-day profile
# from the first install, and the app stopped opening on the original date.
if [[ "${1:-}" != "--force" && -f "$STATE/last_install" ]]; then
  last=$(<"$STATE/last_install")
  age_days=$(( ($(date +%s) - last) / 86400 ))
  expires=0
  [[ -f "$STATE/profile_expires" ]] && expires=$(<"$STATE/profile_expires")
  left_h=$(( (expires - $(date +%s)) / 3600 ))
  if (( age_days < RENEW_AFTER_DAYS && left_h > 48 )); then
    exit 0
  fi
fi

# Reachable? (cable, or Wi-Fi with "Connect via network")
# A sleeping phone lists as "available (paired)" until something asks for it;
# one details call brings the Wi-Fi tunnel up.
xcrun devicectl device info details --device "$UDID" >/dev/null 2>&1 || true
sleep 3
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
# The phone itself as the destination: a free team's profile is generated
# for its registered devices, and a generic build registered none ("Your team
# has no devices").
# A fresh 7-day profile every time: move the cached ones aside and let
# xcodebuild fetch new ones (`flutter build ios` cannot pass
# -allowProvisioningUpdates, so it silently reused the old profile).
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$STATE/old-profiles"
for p in "$PROFILES"/*.mobileprovision(N); do
  if security cms -D -i "$p" 2>/dev/null | grep -q "$BUNDLE"; then
    mv "$p" "$STATE/old-profiles/"
  fi
done
APP="build/xc/Build/Products/Release-iphoneos/Runner.app"
if ! flutter build ios --config-only --release --dart-define-from-file=.env >> "$LOG" 2>&1 ||
   ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
       -destination "id=$UDID" -derivedDataPath build/xc \
       -allowProvisioningUpdates -allowProvisioningDeviceRegistration build >> "$LOG" 2>&1; then
  git checkout -q -- pubspec.lock 2>/dev/null || true
  if tail -200 "$LOG" | grep -q "No Accounts"; then
    log "build FAILED: Xcode is signed out of the Apple ID"
    notify "Erneuerung braucht deine Apple-ID: Xcode › Einstellungen › Accounts › anmelden."
  else
    log "build FAILED"
    notify "Erneuerung fehlgeschlagen (Build). Details: ~/Library/Logs/turbohealth-renew.log"
  fi
  exit 1
fi
git checkout -q -- pubspec.lock 2>/dev/null || true
expires=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null |
  plutil -extract ExpirationDate raw -o - - 2>/dev/null)
expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires" +%s 2>/dev/null || echo 0)
if (( expires_epoch - $(date +%s) < 6 * 86400 )); then
  log "profile is not fresh (expires $expires); not installing"
  notify "Erneuerung abgebrochen: kein frisches Signatur-Profil (läuft ab $expires)."
  exit 1
fi

# Never ship a build without HealthKit (AltStore lesson).
if ! codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q healthkit; then
  log "build has no HealthKit entitlement; not installing"
  notify "Erneuerung abgebrochen: Build ohne HealthKit."
  exit 1
fi

if ! xcrun devicectl device install app --device "$UDID" "$APP" >> "$LOG" 2>&1; then
  log "install FAILED (phone locked or out of reach?); next try later"
  exit 1
fi

# Exactly one Turbo Health, the same bundle: the band must keep one owner.
count=$(xcrun devicectl device info apps --device "$UDID" 2>/dev/null | grep -c "$BUNDLE" || true)
if [[ "$count" != "1" ]]; then
  log "WARNING: found $count installs of $BUNDLE"
fi

date +%s > "$STATE/last_install"
print -r -- "$expires_epoch" > "$STATE/profile_expires"
log "renewed ($(git rev-parse --short HEAD)); profile valid until $expires"
notify "App neu signiert, wieder 7 Tage gültig ($(git rev-parse --short HEAD))."
