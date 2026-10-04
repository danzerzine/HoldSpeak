---
name: Speak!
description: Push-to-talk dictation in the macOS menu bar; a red on-air tally over native system chrome.
colors:
  tally-red: "#ff3b30"
  warn-orange: "#ff9500"
  ok-green: "#34c759"
  icon-salmon-light: "#ffa995"
  icon-salmon-deep: "#f0697c"
  pill-black: "#141418"
  pill-graphite: "#5b5b63"
  pill-blue: "#0a6cff"
  pill-purple: "#7d4cdb"
  pill-pink: "#d63c8a"
  pill-red: "#d9342b"
  pill-orange: "#e07a10"
  pill-green: "#1f9d55"
typography:
  title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 700
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 400
  body-strong:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 600
  callout:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11.5px"
    fontWeight: 400
  callout-strong:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11.5px"
    fontWeight: 600
  caption:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 400
    fontFeature: "tnum"
rounded:
  seg-thumb: "5px"
  seg-track: "7px"
  row: "9px"
  card: "12px"
  alert: "12px"
  hud-classic: "12px"
spacing:
  s1: "4px"
  s2: "8px"
  s3: "12px"
  s4: "16px"
  s5: "20px"
components:
  hud-pill:
    typography: "{typography.body}"
    rounded: "{rounded.hud-classic}"
    height: "40px"
    padding: "0 16px 0 14px"
  hud-pill-tall:
    height: "52px"
  popover:
    typography: "{typography.body}"
    width: "340px"
    padding: "6px 0"
  popover-row:
    rounded: "{rounded.row}"
    typography: "{typography.body}"
  settings-row:
    height: "38px"
    typography: "{typography.body}"
  compact-segmented:
    typography: "{typography.callout}"
    rounded: "{rounded.seg-track}"
    padding: "2px"
  engine-card:
    rounded: "{rounded.card}"
    padding: "14px"
  alert-card:
    rounded: "{rounded.alert}"
    padding: "10px 12px"
  status-badge:
    backgroundColor: "{colors.warn-orange}"
    size: "7px"
  status-badge-error:
    backgroundColor: "{colors.tally-red}"
    size: "7px"
---

# Design System: Speak!

All values below come from `Sources/UI/DesignTokens.swift` (`enum DS`, `PillColor`, the `dsGlass` / `dsProminent` / `dsButton` helpers, `CompactSegmented`) and from how the surfaces use them. Units are points; the frontmatter writes them as px, one to one. Code wins over the concept page wherever the two differ.

## Overview

**Creative North Star: "On Air"**

Speak! should look like a first-party Apple utility that stays out of sight until the hotkey is held, and then lights one red tally, the way a studio lamp says a microphone is live. Everything else is the system's own vocabulary: materials, controls, SF Symbols, semantic colours, the user's accent. The app owns very little of its own visual language on purpose, and that restraint is the identity.

Two renderings of one design ship side by side. On macOS 26 and later (`DS.isGlass`) surfaces use Liquid Glass, capsules and glass buttons. On macOS 14–15 they fall back to `NSVisualEffectView` with the `.popover` material, rounded rectangles, a 0.5 pt hairline and bordered buttons. Every surface has to work in both; `dsGlass`, `dsProminent` and `dsButton` make that switch, so views never branch on the OS for chrome themselves.

Density follows macOS menus and System Settings: 13 pt body, 38 pt grouped rows, 4 pt spacing steps, a 340 pt popover.

**Key Characteristics:**
- One app-owned colour, the red tally; all other colour is system semantic or user-chosen.
- Liquid Glass on 26+, classic materials on 14–15, selected by `DS.isGlass`.
- Seven named text styles; times and counters always use tabular digits.
- State is shown in the menu bar icon itself, before the user speaks.
- Reduce Motion turns every movement into a fade or a still frame.

## Colors

A neutral system palette with one live red; colour means state, never decoration.

### Primary
- **On-Air Tally** (`systemRed`; light-mode value in frontmatter `tally-red`): the menu bar icon background while listening (at 92 % opacity), the HUD recording dot and its 22 % halo, the error badge on the icon, error glyphs in the HUD, and the label of destructive actions (Reset…, Clear History…), as macOS colours them. It appears only while recording, after a failure, or on a destructive action.

### Secondary
- **Needs-Setup Orange** (`systemOrange`, `warn-orange`): the attention badge on the menu bar icon, the popover status dot and the permission alert card (tinted fill), the HUD "Stops in 0:28" countdown in the last 30 s before the recording limit.
- **Ready Green** (`systemGreen`, `ok-green`): the popover "Ready" dot, "Allowed" permission dots, the Downloaded dot on models.

### Tertiary
- **Salmon Icon Gradient** (`icon-salmon-light` to `icon-salmon-deep`): the app icon only (`Resources/AppIcon.icon`). It appears in UI as the icon image in onboarding and nowhere as a fill or text colour.
- **Pill Palette** (`pill-*`): eight solid HUD fills the user picks in Settings → General → Appearance, plus Glass (the system material, the default). On a solid fill all HUD text turns white, secondary text white at 72 %, the tally dot white with a 28 % white halo.

### Neutral
- **System roles**: `Color.primary` / `.secondary` / `.tertiary` for text, `windowBackgroundColor`, `controlBackgroundColor` and `separatorColor` for surfaces and lines, `Color.accentColor` for selection (sidebar row, chosen engine card, selected pill swatch ring, recording keycap border).
- **Primary-tint washes**: hover and inset fills are `Color.primary` at low opacity (0.035 table/inset fill, 0.05–0.06 hover and tags, 0.08 box borders, 0.09 separators, 0.1 classic hairlines). They adapt to light and dark mode with no extra tokens.

### Named Rules
**The One Tally Rule.** The only colour the app asserts on its own is the red tally, and it means "recording", "failed" or "destructive". Any other colour on screen comes from a system semantic role, the user's accent colour, or the user's own pill choice.

**The State-Not-Decoration Rule.** Red, orange and green each map to a state (red: recording, failed or destructive; orange: needs setup; green: ready or done). Never use them as accents, highlights or brand fills.

## Typography

**Display Font:** SF Pro (system font)
**Body Font:** SF Pro (system font)
**Label/Mono Font:** SF Pro with tabular digits for numbers; SF Mono only inside the Gemini key field.

**Character:** The system face at macOS sizes. Weight carries hierarchy (bold, semibold, regular); colour steps carry secondary information.

### Hierarchy
- **Title** (bold, 22 pt): onboarding step titles only.
- **Headline** (bold, 15 pt): the Settings pane title in the header row.
- **Body** (regular, 13 pt): rows, buttons, HUD text, popover menu rows. **Body Strong** (semibold, 13 pt) for emphasised row titles; HUD state words ("Listening", "Transcribing") are body at semibold.
- **Callout** (regular, 11.5 pt): captions under rows, status lines, segmented labels, popover stats. **Callout Strong** (semibold, 11.5 pt): popover section label ("Recent").
- **Caption** (regular, 11 pt, tabular digits): times and counters in history tables.

### Named Rules
**The Named Style Rule.** Text takes its size and weight from a `DS` style. A size that no style covers is a request for a new role in `DesignTokens.swift`, not an inline `.font(.system(size:))`.

**The Tabular Clock Rule.** Elapsed time, counts and WPM figures always use monospaced digits so they do not jitter while updating.

## Layout

Spacing runs on 4 pt steps: s1 4, s2 8, s3 12, s4 16, s5 20. Popover content is inset s4 horizontally; menu rows sit in a 6 pt inset so their hover fill stops short of the edge. Settings groups use `Form` with `.formStyle(.grouped)` and draw no background of their own, so the window colour is continuous under header and groups.

- **Menu bar item**: 22 pt tall; the radio glyph is 17 pt tall with 7 pt side padding. While listening or transcribing the item widens by a 6 pt gap and a 20 pt run of four level bars.
- **HUD**: anchored 6 pt under the menu bar icon, or 30 pt above the bottom of the screen (user choice). Clamped to the screen edges.
- **Popover**: fixed 340 pt wide (`DS.popoverWidth`), vertical stack of header, optional alert, hold hint, recent list, stats, menu rows, quit.
- **Settings**: own two-column shell under a transparent titlebar. An inset sidebar card (194 pt on glass, 210 pt classic) holds the traffic lights, a search field 16 pt below them and the pane list; the content column has a 15 pt bold header on the traffic-light row, with search in the header for Dictionary and History.
- **Onboarding**: fixed 600 × 470 window, four steps (welcome, engine, permissions, try it), footer with Back, centred step dots (6 pt) and a prominent Continue/Done.

## Elevation & Depth

Depth is material first. Glass and `.popover` vibrancy separate surfaces from what is behind them; hairlines (0.5 pt) define edges on classic surfaces. Shadows exist only on the floating HUD and on the segmented-control thumb.

### Shadow Vocabulary
- **HUD solid lift** (black 30 %, radius 15, y 10, plus a 0.5 pt white 16 % hairline): HUD with a solid pill colour.
- **HUD classic lift** (black 22 %, radius 25, y 18, plus a 0.5 pt primary 10 % hairline): glass HUD on macOS 14–15. On 26+ the system glass supplies its own depth.
- **Thumb lift** (black 15 %, radius 1, y 1): the selected thumb in the compact segmented control.

### Named Rules
**The Material-First Rule.** Popover, sidebar and HUD get depth from the system material, not from drawn shadows. A new floating surface uses `dsGlass`; it does not invent its own shadow.

## Shapes

Continuous macOS corners, sized by component: segmented thumb 5 / track 7, keycap 6, popover rows 9, cards and alerts 12, classic HUD 12. On macOS 26 the HUD and the compact segmented control become capsules, matching the system controls there. Boxed tables (History, Dictionary) and the Settings sidebar card use 14 pt on glass and 10 pt classic; this pair is currently written inline, not in `DS`. Borders are hairlines: 0.5 pt on materials, 1 pt at primary 8 % around boxed tables; a selection border is 2 pt accent.

## Components

### Buttons
- **Primary**: `dsProminent()`; prominent glass on 26+, blue `.borderedProminent` on 14–15. Used once per surface for the forward action (Continue/Done, Download, Retry).
- **Ordinary**: `dsButton()`; glass or `.bordered`.
- **Destructive**: plain bordered button whose label is tally red (Reset…, Clear History…; secondary when there is nothing to clear), confirmed by an `NSAlert`.
- **Menu rows** (popover): full-width plain buttons, body text, trailing shortcut in secondary, primary 6 % hover fill at 9 pt radius.

### Chips (Dictionary variants)
- **Style:** 11 pt text on primary 6 % fill, 4 pt radius, 6 × 1 pt padding.
- **Overflow:** only whole variants that fit are shown, then a tertiary "+N".

### Cards / Containers
- **Engine card** (onboarding): 12 pt radius, 14 pt padding, primary 3.5 % fill with a 1 pt primary 6 % border; selected is accent 8 % fill with a 2 pt accent border. Leading SF Symbol in accent colour.
- **Alert card** (popover permissions): 12 pt radius, orange tint fill, warning glyph, explanatory callout and one action.
- **Boxed table** (History, Dictionary): 14/10 pt radius, 1 pt primary 8 % border, primary 3.5 % footer strip.

### Inputs / Fields
- **Compact segmented** (`CompactSegmented`): grey track (primary 6 %), `controlBackgroundColor` thumb with thumb lift, 11.5 pt labels, 9 pt horizontal padding. Used inside settings rows instead of the system segmented control, which on 26 is larger and fills the choice blue.
- **Hotkey keycap**: `controlBackgroundColor` fill, 6 pt radius, 0.5 pt primary 14 % border, one line, min 110 pt wide; while recording the border becomes 2 pt accent and the label reads "Press a key…".
- **Search**: plain text field on a primary 5 % fill at 7 pt radius, magnifier glyph.

### Navigation
- **Settings sidebar**: 20 pt rounded-square tiles (5 pt radius) in System Settings colours with a white SF Symbol; row text body; selected row fills accent with white text at 7 pt radius; hover is primary 5 %.
- **Onboarding**: Back (hidden on the first step), 6 pt step dots (current primary, others primary 30 %), prominent Continue that stays disabled until the step's requirement is met.

### Menu Bar Icon (signature)
The walkie-talkie glyph from `Resources/radio.svg`, lying on its right side, rendered into the status button's image (subviews over the button are invisible). Six states from `AppStatus.IconState`:
- **Ready**: glyph alone, template colour.
- **Listening**: white glyph on a tally-red 6 pt rounded background, with four live level bars (2.5 pt wide, 2 pt apart, 3–14 pt tall).
- **Transcribing**: grey 26 % background, bars shimmer in a 1 s ease-in-out wave staggered 0.15 s.
- **Loading**: glyph at 40 % with a spinning 30 % arc ring (18 pt, 1.6 pt stroke).
- **Attention / Error**: 7 pt orange or red badge at top right with a 0.75 pt dark outline.
- **Inserted**: the glyph pops to 1.25× and back over 0.45 s.

### HUD Pill (signature)
A capsule (26+) or 12 pt rounded rectangle (14–15), 40 pt tall, 52 pt when it carries a second line; 14 pt leading and 16 pt trailing padding, 10 pt between parts.
- **Listening**: tally dot 8 pt in a 16 pt halo, "Listening" semibold, 96 × 24 pt waveform (24 bars, 2.5 pt wide, 4 pt pitch, older bars fade), elapsed time in tabular digits, language code.
- **Transcribing**: spinner, "Transcribing", engine short name.
- **Message**: a 16 pt column glyph (warn triangle orange, error triangle red, lock secondary, spinner) and a title over a one-line detail.
- **Motion**: drops in with `DS.hudSpring` (response 0.38, damping 0.82). With Reduce Motion it fades in 0.15 s and changes content with no animation.
- **Accessibility**: the pill is one combined element, and every state change is announced to VoiceOver through `Announce.say` at high priority.

## Do's and Don'ts

### Do:
- **Do** take every size, radius and text style from `DS`, and add a named role there when none fits.
- **Do** build floating surfaces with `dsGlass` and primary actions with `dsProminent`, so both the Liquid Glass and the classic rendering stay correct.
- **Do** show readiness in the menu bar icon and popover status line (green ready, orange needs setup, grey loading) before the user speaks.
- **Do** replace movement with a fade or a still frame when `DS.reduceMotion` is on: no spring, no shimmer, no spinning ring, no icon pop.
- **Do** announce HUD state changes to VoiceOver and give the menu bar icon a state-specific label ("Speak!, listening").
- **Do** render menu bar states into the status button image.

### Don't:
- **Don't** introduce an app-owned colour besides the red tally; use system semantic colours, the accent colour or the user's pill choice.
- **Don't** use red, orange or green for anything except their states.
- **Don't** write `.font(.system(size:))` in a view.
- **Don't** use the app icon's salmon gradient as a UI fill or text colour.
- **Don't** replace the walkie-talkie glyph with an SF Symbol microphone, or stand it upright.
- **Don't** place SwiftUI or AppKit subviews over the status bar button; they do not show.
