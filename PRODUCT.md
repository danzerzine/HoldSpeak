# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users
Russian-speaking developers like Daniyar who dictate prompts to AI coding agents (Claude Code, Codex, chat UIs) all day. They mix Russian and English in one sentence and use IT terms constantly (pull request, rebase, Kubernetes). Dictation happens dozens of times a day, mid-task, with the eyes on another app. A wider public audience from GitHub releases is secondary (Daniyar, 04.10.2026).

## Product Purpose
Push-to-talk dictation that lives in the macOS menu bar: hold a hotkey, speak, release, and the text lands in the focused input field. Its reason to exist is throughput: speech runs two to three times faster than typing, and typing has become the ceiling on iterating with AI agents. Success means the user forgets the app is there until the moment they hold the key, and never loses a dictation.

## Positioning
Local by default (NVIDIA Parakeet through FluidAudio, or Whisper through WhisperKit, on the Mac's GPU) with an optional Google Gemini engine on the user's own API key. A per-language correction dictionary turns misrecognized transliterations into canonical IT terms, and it can be filled from any app through the "Fix Spelling in Speak!" service. Free fork of timmal/HoldSpeak, renamed Speak! (repo danzerzine/Speak).

## Operating Context
- Menu bar app (LSUIElement): no Dock icon, no Cmd-Tab entry. Surfaces: menu bar icon, popover, HUD pill under the menu bar icon or at the bottom of the screen while recording, Settings window (General, Shortcut, Recognition, Dictionary, History), onboarding window, system notifications.
- Two configurable hotkeys (default Right Option); short presses are discarded by a hold threshold.
- Text insertion without the clipboard; password fields are skipped.
- History of recent transcriptions (click to copy), metrics (dictations today/yesterday, 7-day average WPM).
- Failed dictations keep the audio and offer Retry in the popover.
- Requires Microphone, Accessibility and Input Monitoring permissions.

## Capabilities and Constraints
- Supported systems: macOS 14 and later. Liquid Glass on macOS 26+, classic look on 14–15; every design must work in both (Daniyar, 04.10.2026).
- SwiftUI + AppKit, built with XcodeGen (`project.yml`). No web stack.
- Engines and models: Parakeet Ultra (~610 MB, default), Whisper Tiny/Small/Turbo, Gemini 3.5 Transcribe / 3.5 Flash-Lite. Gemini key lives in the Keychain.
- Agents cannot screenshot the running app (see project memory); visual checks of the real build need Daniyar's eyes or screenshots.
- The 04.10.2026 redesign closed the audit gaps: the menu bar icon shows readiness, the popover shows the engine and recent dictations, failed and not-inserted dictations are marked. Design system: `DESIGN.md`.

## Brand Commitments
- Name: Speak! (app bundle Speak.app; formerly HoldSpeak). Logo and menu bar glyph: a walkie-talkie / radio (`radio.svg`, `docs/screenshots/logo.webp`).
- Should feel like a first-party Apple app: native macOS conventions, system materials and controls (Daniyar, 04.10.2026: "сделай идеальное apple приложение").

## Evidence on Hand
- README hero image `docs/screenshots/hero.webp`, regenerated from demo data by `scripts/readme-screenshots.sh`.
- Measured speed: a ~10 s phrase appears ~0.5 s after release with Parakeet on an M1 MacBook Air (3 log samples, 0.36–0.83 s).
- No testimonials or user counts exist; none may be invented.

## Product Principles
1. Invisible until held: the app never demands attention outside the act of dictating.
2. Never lose speech: every failure is visible, explained, and recoverable.
3. State at a glance: readiness (model, key, permissions) is visible before the user speaks, not discovered after a failed dictation.
4. Local first, cloud by choice.
5. Native over custom: system controls and conventions win over bespoke widgets.

## Accessibility & Inclusion
Respect Reduce Motion, Increase Contrast and larger system text; VoiceOver labels on the menu bar icon and HUD state changes.
