#!/usr/bin/env bash
# Build a signed .app, package as DMG, create a GitHub release.
# Usage: ./scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>   e.g. $0 0.2.0"
  exit 1
fi
TAG="v$VERSION"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. brew install gh"
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  echo "Release from main, not $BRANCH."
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Working tree has uncommitted changes; commit or stash them first."
  exit 1
fi
git fetch -q origin main
AHEAD="$(git rev-list --count origin/main..HEAD)"

# Bump versions in project.yml and Resources/Info.plist (xcodegen copies one into the other).
BUILD_NUMBER="$(git rev-list --count HEAD)"
/usr/bin/sed -i '' "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$VERSION\"/" project.yml
/usr/bin/sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
/usr/bin/sed -i '' "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$BUILD_NUMBER\"/" project.yml

xcodegen generate >/dev/null

pkill -x Speak 2>/dev/null || true
pkill -x HoldSpeak 2>/dev/null || true
chmod -R u+w build dist 2>/dev/null || true
rm -rf build dist 2>/dev/null || true
mkdir -p build dist
xcodebuild -scheme Speak -configuration Release \
  -derivedDataPath build clean build 2>&1 | tail -5

APP_SRC="build/Build/Products/Release/Speak.app"
mkdir -p dist
cp -R "$APP_SRC" "dist/Speak.app"

IDENTITY="HoldSpeak Dev (self-signed)"
if security find-identity -v -p codesigning login.keychain-db 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "dist/Speak.app"
else
  codesign --force --deep --sign - "dist/Speak.app"
fi

# Build DMG
STAGING="dist/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "dist/Speak.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="dist/Speak-$VERSION.dmg"
hdiutil create -volname "Speak $VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG"

rm -rf "$STAGING"

# Commit version bump
git add project.yml Resources/Info.plist
git commit -m "release: $TAG" || true
git tag -a "$TAG" -m "Release $TAG"

echo
echo "DMG built: $DMG"
echo "Pushing publishes main ($AHEAD earlier unpushed commits + the version bump), tag $TAG and a GitHub release."
read -r -p "Push and publish? [y/N] " ANSWER
if [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]]; then
  echo "Stopped before push. The commit and tag stay local; undo with: git tag -d $TAG && git reset --hard HEAD~1"
  exit 0
fi
git push origin main
git push origin "$TAG"

# GitHub release
gh release create "$TAG" "$DMG" \
  --title "Speak! $VERSION" \
  --generate-notes

echo
echo "Released $TAG"
echo "DMG: $DMG"

# Relaunch the installed app so the user isn't left without Speak! running
if [[ -d /Applications/Speak.app ]]; then
  open /Applications/Speak.app
fi
