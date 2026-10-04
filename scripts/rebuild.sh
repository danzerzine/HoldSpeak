#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Ensure xcodeproj is up to date
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

# Kill running instance
pkill -x HoldSpeak 2>/dev/null || true

# Build. Release keeps dictated text out of HoldSpeak.log (only its length is
# logged); CONFIG=Debug ./scripts/rebuild.sh logs the text for debugging. -O makes
# FluidAudio's term rescoring ~5x faster (≈60 ms instead of ≈290 ms per phrase).
CONFIG="${CONFIG:-Release}"
xcodebuild -scheme HoldSpeak -configuration "$CONFIG" \
  -derivedDataPath build \
  SWIFT_OPTIMIZATION_LEVEL=-O \
  clean build 2>&1 | tail -5

APP_SRC="build/Build/Products/$CONFIG/HoldSpeak.app"
APP_DST="/Applications/HoldSpeak.app"

rm -rf "$APP_DST"
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
