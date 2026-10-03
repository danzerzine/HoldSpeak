#!/usr/bin/env bash
# Weekly: fetch timmal/HoldSpeak and show a notification if upstream/main has
# commits we haven't been told about yet. Only reads; never merges.
# Run by ~/Library/LaunchAgents/com.daniyar.holdspeak-upstream.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

STATE="$HOME/Library/Application Support/HoldSpeak/upstream-last-seen"
git fetch -q upstream

tip=$(git rev-parse upstream/main)
seen=$(cat "$STATE" 2>/dev/null || git merge-base main upstream/main)
[[ "$tip" == "$seen" ]] && { echo "$(date '+%F %T') no new upstream commits"; exit 0; }

count=$(git rev-list --count "$seen..$tip")
latest=$(git log -1 --format=%s "$tip")
echo "$(date '+%F %T') $count new upstream commit(s):"
git log --oneline "$seen..$tip"

# Pass text as arguments so quotes in commit subjects can't break the AppleScript.
osascript -e 'on run argv' \
  -e 'display notification (item 2 of argv) with title "HoldSpeak upstream" subtitle (item 1 of argv)' \
  -e 'end run' "$count new commit(s) from timmal" "Latest: $latest"

mkdir -p "$(dirname "$STATE")"
echo "$tip" > "$STATE"
