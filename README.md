<p align="center">
  <img src="docs/screenshots/logo.webp" width="180" alt="Speak! logo" />
</p>

# Speak!

Formerly HoldSpeak. A fork of [timmal/HoldSpeak](https://github.com/timmal/HoldSpeak) with a Parakeet engine, a correction dictionary you can fill from any app, and other changes. [Download](https://github.com/danzerzine/HoldSpeak/releases/latest)

Local push-to-talk dictation for macOS. Speak! is a **menu bar app** (no Dock icon, no windows in the way) — it lives in the status bar and stays out of your workflow until you hold the hotkey. Speak, release — recognized text is inserted into the focused input. Local by default: Whisper runs on GPU via WhisperKit. Optionally, you can switch to Google Gemini with your own API key.

<p align="center">
  <img src="docs/screenshots/popover.webp?v=4" width="360" alt="Menu bar popover" />
</p>

A free, local alternative to paid Whisper wrappers. Built for one reason: talking to AI is faster than typing to it. Average typing speed hovers around 40–60 wpm; comfortable speech is 130–160 wpm — two to three times faster. As more of the dev loop moves into prompts to AI agents, raw typing throughput becomes a real ceiling on how quickly you can iterate. Speak! lifts it: hold the hotkey, speak a full thought, release, it lands in the input.

## Features

- **Local transcription** with NVIDIA Parakeet (FluidAudio) by default, or Whisper models through WhisperKit (CoreML, GPU)
- **Optional cloud engine** — Google Gemini with your own API key, for higher accuracy on mixed-language speech and jargon
- **Code-switching RU/EN/UK and more** — in auto mode the language is chosen only from the ones you have in System Settings → Language & Region
- **Insertion without clipboard** — via `CGEventKeyboardSetUnicodeString`; password fields are skipped
- **Menu bar popover** with recent transcriptions (click to copy) and metrics: dictations today / yesterday, 7-day avg WPM
- **HUD overlay** while you hold the key: dark pill with a live mic level; if a dictation fails (no model, bad API key, quota), the reason shows in the same pill
- **Light text cleanup** — trims long "eeeeee / mmmmm / ummm", collapses 3+ consecutive repeats, capitalizes the first letter and adds a period
- **Liquid Glass** on macOS 26 and later — the HUD, popover, Preferences and onboarding use the system glass; macOS 14–15 keep the classic look
- **Terminology dictionary** — canonical IT terms (pull request, Kubernetes, Claude Code, …) replace misrecognized Russian transliterations in transcripts; ships with ~110 defaults and is fully editable

## Install

Grab the latest DMG from the [Releases page](https://github.com/danzerzine/HoldSpeak/releases/latest), open it, and drag `Speak.app` into `Applications`.

Because the app is self-signed, macOS will block the first launch. Open **System Settings → Privacy & Security**, scroll to the message *"Speak was blocked…"* and click **Open Anyway**. Confirm with Touch ID / password. After that it launches normally from Launchpad / Applications. The app runs as a menu bar extra — look for the radio icon in the right side of your menu bar; it won't appear in the Dock or Cmd-Tab.

On first launch, choose how speech is recognized — **on this Mac** (downloads Parakeet Ultra, ~610 MB) or **Gemini** (Google cloud, asks for your API key) — and the language you mostly dictate in (it starts on your system language), then grant three permissions:

- **Microphone** — for audio capture
- **Accessibility** — for the global hotkey and text insertion
- **Input Monitoring** — to use Right Option / Right Cmd (or the hotkey you choose) as push-to-talk

The onboarding window has Open… and Re-check buttons.

<p align="center">
  <img src="docs/screenshots/onboarding.webp?v=4" width="480" alt="Onboarding · choose Whisper or Gemini" />
</p>

### Updating

The app checks GitHub for new versions in the background and shows an **Update available** banner in the menu bar popover. You can also trigger a check manually via Preferences → General → **Check for updates**.

1. Click **Download** in the banner — it opens the latest release on GitHub.
2. Download the `.dmg`, open it, and drag `Speak.app` into `Applications`. macOS will ask to replace the old copy — confirm.
3. Quit the running app from the menu bar (Quit), then launch the new one from `Applications`.

Your preferences, history, and downloaded models live in `~/Library/Application Support/Speak/` and are preserved across updates.

**Coming from HoldSpeak.** Speak! is the same app under a new name and bundle id. On first launch it moves your models, history and dictionaries from `Application Support/HoldSpeak` and copies your preferences. macOS treats it as a new app, though: grant Microphone, Accessibility and Input Monitoring once more (the welcome window opens on that step), allow Keychain access to the Gemini key when asked, and delete `HoldSpeak.app` from `Applications`.

### Model

The default is **Parakeet Ultra (~610 MB)** — fast and accurate for Russian and English. You can switch to a Whisper model (Tiny, Small, Turbo) in Preferences → Audio; installs that were on Turbo stay on it after an update.

If you already have MacWhisper / another WhisperKit client installed, their models will be picked up automatically. Otherwise the first model is downloaded to `~/Library/Application Support/Speak/models/`.

To free disk space, Preferences → Audio → **Downloaded models → Delete…** removes every model Speak! downloaded. Models that belong to MacWhisper or other apps are left alone.

### Gemini (optional, cloud)

Pick a Gemini model in Preferences → Audio → **Model** (or choose Gemini during onboarding) and paste an API key:

1. Create a key at [Google AI Studio → API keys](https://aistudio.google.com/apikey).
2. **Set up billing** for the key's project in AI Studio. Without billing the key runs on the free tier, which stops after a couple dozen dictations a day — Speak! then shows *"Gemini daily limit reached — set up billing"* in the HUD.
3. Paste the key in Speak! and click **Save**. The key is checked with Google and stored in the macOS Keychain, never in preferences files; it survives app updates. After each update macOS asks once to let the new version read the key — enter your Mac password and click **Always Allow** (Speak! is self-signed, so the Keychain sees every new build as a new app).

<p align="center">
  <img src="docs/screenshots/preferences-audio-gemini.webp?v=4" width="560" alt="Preferences · Audio with Gemini selected" />
</p>

Models:

- **3.5 Transcribe** (default) — dedicated speech-to-text, ~2 s per dictation, about **$0.30 per hour of speech**.
- **3.5 Flash-Lite** — cheaper (~$0.06/hour) and better at following the terminology dictionary, but response time varies more.

If something goes wrong, the reason appears right in the HUD pill instead of a silent empty result:

<p align="center">
  <img src="docs/screenshots/hud-quota.webp?v=4" width="334" alt="HUD · Gemini daily limit reached" />
</p>

Privacy: with Gemini, each dictation's audio is sent to Google. Whisper stays the default and never sends anything anywhere. Text cleanup, the "Add period" / "Capitalize" options and the terminology dictionary apply to both engines; Gemini also receives your dictionary's terms as spelling hints.

### Reducing insertion latency

The delay between releasing the hotkey and text appearing in the input is dominated by the Whisper forward pass. Two levers:

- **Pick a smaller model.** Preferences → Audio → *Model*:
  - **Tiny (~75 MB)** — fastest (~80–150 ms on Apple Silicon for a short utterance), lowest quality. Good for quick English/single-language dictation.
  - **Small (~470 MB)** — middle ground.
  - **Turbo (~1.5 GB)** — the best Whisper, but ~400–800 ms per utterance.
  - **Parakeet Ultra (~610 MB)** — default. NVIDIA Parakeet (a post-trained v3), run with FluidAudio instead of WhisperKit. About 20× faster than Whisper on the same Mac, 25 languages including Russian and Ukrainian. It detects the language itself, so the Primary language setting does not apply to it. Needs macOS 14.
- **Set a fixed language** instead of Auto. Preferences → Audio → *Primary language*: picking Russian or English skips an extra language-detection forward pass that Auto mode runs before transcription.

Combining **Tiny + explicit language** gives the lowest end-to-end latency. Combining **Turbo + Auto** gives the best quality but is the slowest path.

## Usage

1. Hold **Right Option** or **Right Command** (the two default hotkeys; change either, or switch the second one off, in Preferences → General).
2. Speak. A HUD appears in the top right corner (or bottom center — configurable) showing the mic level.
3. Release the key. After ~1–2 s the text is inserted into the focused field.
4. If the field lost focus — open the menu bar icon: it shows the recent transcriptions; click to copy.

### Short taps

Recording starts the moment you press the hotkey, so the first syllable isn't lost. Presses shorter than **150 ms** are discarded, and so is a hold during which you press another key: Option+letter or Command+C stays a shortcut instead of becoming a dictation. If the hotkey is a key combination such as ⌥Space, a short tap still reaches the app as that keystroke. The threshold is configurable in Preferences → General (50–800 ms).

A bare letter can't be a hotkey: it would stop typing everywhere. Use a modifier on its own, a key with ⌃/⌥/⌘, or an F-key.

If recognition fails (the local model throws, Gemini is unreachable or out of quota), the HUD says so and the menu bar popover offers **Retry**: the audio of the last failed dictation is kept in memory until the next successful one.

## Preferences

- **General** — two hotkeys (the second can be switched off), hold threshold, HUD position (under the icon / bottom center), theme (Auto / Light / Dark), launch at login, update check
- **Audio** — microphone, language, model (Whisper or Gemini), model download / deletion, Gemini API key
- **Terms** — terminology dictionary (see below)
- **History** — clear history and reset metrics

<p align="center">
  <img src="docs/screenshots/preferences-general.webp?v=4" width="560" alt="Preferences · General" />
  <br /><br />
  <img src="docs/screenshots/preferences-audio.webp?v=4" width="560" alt="Preferences · Audio" />
</p>

### Auto language detection

In Auto mode the app reads `Locale.preferredLanguages` from the system and restricts Whisper to those languages only. So if macOS has RU, EN, UK enabled, Whisper will pick among them and won't drift into, say, Bulgarian.

When two of your preferred languages score close in detection (e.g. a sentence mixes Russian with English terms), the app drops the forced language for that utterance and lets Whisper switch per-segment — this tends to preserve English terms verbatim instead of transliterating them.

### Terminology dictionary

Whisper reliably recognizes common speech but routinely mangles IT terminology in mixed RU+EN dictation (`пулл реквест` instead of `pull request`, `кубернетес` instead of `Kubernetes`, and so on). The **Terms** tab lets you map your spoken variants to a single canonical form, which is then substituted in the transcript before it's inserted. Each Primary language keeps its own set of terms. With a Whisper model in Auto mode the active set follows the detected language of the current utterance; Parakeet and Gemini don't report a language, so with them the set stays on your Primary language (or the last detected one).

With Parakeet the dictionary also works by sound. A small keyword model (parakeet-ctc-110m, ~98 MB, downloaded the first time Parakeet loads) listens for words that sound like a term with a Latin spelling and swaps that spelling in, so `пул реквист` and `Basicampi` come out as `pull request` and `Basecamp` even when that exact misspelling is not in your list. It adds about 60–80 ms per phrase. Whisper is not affected.

> **Tip.** If Whisper keeps mangling the same word or name — a project codename, a library you use daily, a colleague's surname — stop fighting the model. Select the wrong word right where it was inserted, right-click it and pick **Fix Spelling in Speak!**, then type the correct spelling and press Return. Next time the word shows up it'll come out right without any hand-editing. That's the whole point of this feature: if you have to fix the transcript by hand every time, it's not dictation — it's a slower way to type. Teach the app once, save the corrections forever.

<p align="center">
  <img src="docs/screenshots/preferences-terms.webp?v=4" width="560" alt="Preferences · Terms" />
</p>

**Default dictionaries.** The app ships with curated IT defaults for **Russian (~110 entries)**, **English (~120)**, and **Ukrainian (~130)** — all spanning the whole dev cycle: VCS (pull request, rebase, cherry-pick), languages (TypeScript, Swift, Rust), frontend (React, Tailwind, Next.js), UX (wireframe, mockup, accessibility), backend (endpoint, middleware, migration), data (Postgres, Redis, ClickHouse), DevOps (Docker, Kubernetes, Helm chart), cloud (AWS, S3, Lambda), and AI tooling (Claude, MCP, Opus). On first launch the bundled lists are copied into your Application Support directory — from then on the files are yours.

**Switching languages in the editor.** Preferences → Terms has a **Dictionary for** picker (top-right). It opens on the dictionary dictation uses right now; switch it to edit another language's set, for example to seed an English dictionary before you dictate in English. Browsing another dictionary doesn't change which one dictation uses.

**How updates work.** App updates do **not** touch your dictionary — your edits, additions, and deletions persist verbatim. To pull in new entries from the latest bundled default, open Preferences → Terms and click **Load defaults…**:

- **Merge** — adds only canonical forms that aren't already in your list. Existing entries and your custom terms are untouched.
- **Replace** — discards your list entirely and reloads the bundled defaults. Use with care.

**Adding your own terms.** The top of the Terms tab is one row: **Transcribed as** → **Should be**. Type what came out (`бойскап`), press Return, type what it should be (`Basecamp`), press Return again. If `Basecamp` is already in the list, the new spelling joins it; otherwise a new term starts. A spelling belongs to one term only, so adding it moves it from any other term. The list reads the same way: `бойскап, бейскэмп → Basecamp`. The pencil opens the full editor for a term (all spellings, one per line, and a case-sensitive switch). Matching is case-insensitive by default and respects word boundaries, so `пулреквест` won't hit inside `пулреквестер`.

**Fixing a word from any app.** Select a misheard word anywhere — the text field you just dictated into, a note, a browser — right-click it and choose **Fix Spelling in Speak!** (in some apps it sits under **Services**). Preferences open on the Terms tab with the word already in *Transcribed as* and the cursor in *Should be*. To use a keyboard shortcut instead, assign one in System Settings → Keyboard → Keyboard Shortcuts → Services → Text.

The Preferences window can be resized; 560×428 is its minimum.

**Import / Export.** Import asks whether to add the file's terms to your list or replace it, and says so if the file isn't a dictionary export. Deleting a term shows **Undo** under the correction row. Pure JSON — commit it to a dotfiles repo, share with a team, seed a new machine.

**Storage.** `~/Library/Application Support/Speak/terminology/<lang>.json` (one file per language: `ru.json`, `en.json`, `uk.json`, …).

## Architecture

- `Sources/Core` — pure logic (hotkey, recorder, inserter, text cleaner, storage, metrics, Gemini API client, Keychain)
- `Sources/Whisper` — transcription engines: WhisperKit (local) and Gemini (cloud) behind one `TranscriptionEngine` facade, model manager
- `Sources/UI` — SwiftUI: menu bar popover, preferences, onboarding, HUD
- `Sources/App` — AppDelegate and entry point

Transcription history is stored in a GRDB-SQLite database at `~/Library/Application Support/Speak/history.sqlite` (most recent 100 entries are kept).

## Logs

Diagnostic events go to `~/Library/Logs/Speak.log`. Useful for microphone / language detection / hotkey issues:

```bash
tail -f ~/Library/Logs/Speak.log
```

## Troubleshooting

**Hotkey doesn't fire.** Check Input Monitoring and Accessibility in System Settings → Privacy & Security. When the signature changes (e.g. a fresh ad-hoc build) TCC may drop entries — delete and re-add, or run `scripts/setup-signing.sh` and rebuild.

**Recognizes silence / empty result.** Check the input level in System Settings → Sound → Input. In the logs, look at `finalize: rms=...` — normal speech is ≥ 0.02. If you see `0.0005` the mic is quiet (wrong device / muted / mic TCC not granted).

**Confuses Ukrainian / Russian with English in auto.** Auto relies on `Locale.preferredLanguages`. Make sure the language is actually listed in System Settings → Language & Region, or switch Preferences → Audio from Auto to an explicit Russian / English.
