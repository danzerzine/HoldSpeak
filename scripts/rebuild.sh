#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Ensure xcodeproj is up to date
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

# Build. Release keeps dictated text out of Speak.log (only its length is
# logged); CONFIG=Debug ./scripts/rebuild.sh logs the text for debugging. -O makes
# FluidAudio's term rescoring ~5x faster (≈60 ms instead of ≈290 ms per phrase).
# Background priority and half the cores keep the Mac usable while it builds;
# incremental, so the packages compile once. CLEAN=1 forces a full rebuild.
CONFIG="${CONFIG:-Release}"
JOBS=$(( $(sysctl -n hw.ncpu) / 2 ))
ACTIONS="build"
if [[ -n "${CLEAN:-}" ]]; then ACTIONS="clean build"; fi
taskpolicy -b xcodebuild -project Speak.xcodeproj -scheme Speak -configuration "$CONFIG" \
  -derivedDataPath build -jobs "$JOBS" \
  SWIFT_OPTIMIZATION_LEVEL=-O \
  $ACTIONS 2>&1 | tail -5

# Quit the running app only after a successful build (HoldSpeak is the name before Speak!).
pkill -x Speak 2>/dev/null || true
pkill -x HoldSpeak 2>/dev/null || true

APP_SRC="build/Build/Products/$CONFIG/Speak.app"
APP_DST="/Applications/Speak.app"

rm -rf "$APP_DST" /Applications/HoldSpeak.app
cp -R "$APP_SRC" "$APP_DST"

# Sign with persistent self-signed identity so TCC grants survive rebuilds.
# Falls back to ad-hoc if the cert isn't installed.
IDENTITY="HoldSpeak Dev (self-signed)"
if security find-identity -v -p codesigning login.keychain-db 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "$APP_DST"
else
  echo "Note: run scripts/setup-signing.sh once for persistent TCC grants."
  codesign --force --deep --sign - "$APP_DST"
fi

echo "Installed to $APP_DST"
open "$APP_DST"
