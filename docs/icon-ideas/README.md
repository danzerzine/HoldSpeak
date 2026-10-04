# Menu bar icon ideas

Alternatives to the current walkie-talkie glyph (`Resources/radio.svg`), which at 16 px in the menu bar looks like a vape. Drawn on 4 October 2026; the current icon stays for now.

| File | Idea |
|---|---|
| `1-pill-wave.svg` | A pill with a short waveform, the same shape as the recording HUD |
| `2-option-key-wave.svg` | The ⌥ key with sound waves: the hotkey plus voice |
| `3-speech-bubble.svg` | A speech bubble with a waveform inside |
| `4-microphone.svg` | A plain microphone |
| `5-button-waves.svg` | A pressed button with radio waves on both sides |
| `6-walkie-talkie-upright.svg` | The walkie-talkie redrawn upright and wider, so it no longer reads as a vape |

All are 24×24 outline glyphs in `currentColor`, so macOS can tint them as a template image. To switch, replace `Resources/radio.svg` with one of these and rebuild; the app icon (`Resources/AppIcon.icns`) would need a matching redraw.
