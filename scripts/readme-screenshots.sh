#!/usr/bin/env bash
# Renders the README images into docs/screenshots from the installed app:
# SPEAK_SNAPSHOT draws every screen to PNG at 2x, SPEAK_DEMO swaps in a throwaway
# history (a busy day of dictation) so your own history never reaches the README.
# Needs ImageMagick (magick) and cwebp. Run after ./scripts/rebuild.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/screenshots
RAW=$(mktemp -d)
trap 'rm -rf "$RAW"' EXIT

SPEAK_DEMO=1 SPEAK_SNAPSHOT="$RAW" /Applications/Speak.app/Contents/MacOS/Speak >/dev/null 2>&1

# Rounded corners, a hairline and a soft shadow on a transparent background,
# so the image sits well on GitHub's light and dark themes.
frame() { # in out radius
  local w h
  w=$(magick identify -format %w "$1"); h=$(magick identify -format %h "$1")
  magick -size "${w}x${h}" xc:none -fill white -draw "roundrectangle 0,0 $((w-1)),$((h-1)) $3,$3" "$RAW/mask.png"
  magick "$1" -alpha set "$RAW/mask.png" -compose DstIn -composite \
    -fill none -stroke 'rgba(0,0,0,0.12)' -strokewidth 2 -draw "roundrectangle 1,1 $((w-2)),$((h-2)) $3,$3" "$RAW/r.png"
  magick "$RAW/r.png" \( +clone -background 'rgba(0,0,0,0.28)' -shadow 60x28+0+20 \) +swap \
    -background none -layers merge +repage "$2"
}

frame "$RAW/popover.png" "$RAW/popover-framed.png" 24
for pane in recognition dictionary history; do
  frame "$RAW/settings-$pane.png" "$RAW/f-settings-$pane.png" 32
done
frame "$RAW/onboarding-1.png" "$RAW/f-onboarding.png" 32

# The black recording pill, cut along its own edge (found from its dark pixels).
geo=$(magick "$RAW/hud-black-listening.png" -colorspace gray -threshold 30% -negate -trim -format '%wx%h%O' info:)
magick "$RAW/hud-black-listening.png" -crop "$geo" +repage "$RAW/pill.png"
w=$(magick identify -format %w "$RAW/pill.png"); h=$(magick identify -format %h "$RAW/pill.png")
magick -size "${w}x${h}" xc:none -fill white -draw "roundrectangle 0,0 $((w-1)),$((h-1)) $((h/2)),$((h/2))" "$RAW/mask.png"
magick "$RAW/pill.png" -alpha set "$RAW/mask.png" -compose DstIn -composite "$RAW/r.png"
magick "$RAW/r.png" \( +clone -background 'rgba(0,0,0,0.35)' -shadow 60x18+0+14 \) +swap \
  -background none -layers merge +repage "$RAW/hud-framed.png"

# Hero: the menu and the recording pill on the app icon's salmon, lightened.
ph=$(magick identify -format %h "$RAW/popover-framed.png")
W=1600; H=$((ph + 250))
magick -size "${W}x${H}" gradient:'#ffe1d6'-'#f7b3bd' \
  "$RAW/popover-framed.png" -gravity north -geometry +0+40 -composite \
  "$RAW/hud-framed.png" -gravity south -geometry +0+50 -composite \
  \( -size "${W}x${H}" xc:none -fill white -draw "roundrectangle 0,0 $((W-1)),$((H-1)) 40,40" \) \
  -alpha set -compose DstIn -composite "$RAW/f-hero.png"

for f in "$RAW"/f-*.png; do
  name=$(basename "$f" .png); name=${name#f-}
  cwebp -quiet -q 90 -alpha_q 100 "$f" -o "$OUT/$name.webp"
done
echo "Wrote $(ls "$RAW"/f-*.png | wc -l | tr -d ' ') images to $OUT"
