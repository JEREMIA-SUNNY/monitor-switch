# Changelog

All notable changes to Monitor Switch.

## 1.1.0 (2026-11-05): Voice commands

### Added
- **Voice commands.** Say *"switch to laptop"* or *"switch to PC"* (*"switch to computer"* and *"switch to desktop"* also work). Turn it on with right-click → **Voice commands**.
  - It uses the speech recognizer built into Windows, so it works offline. Audio stays on your computer: nothing is recorded, saved or sent anywhere.
  - It only listens for its own phrases. A phrase is accepted only when the recognizer is at least 70% sure (`$VoiceConfidence`), so normal talking or a video doesn't trigger it.
  - The phrases and the confidence level can be changed at the top of `MonitorSwitch.ps1`.
  - Your choice is remembered, so voice turns back on by itself after a restart.
  - Clear messages appear if there's no microphone, if Windows has no speech recognizer, or if the microphone stops while listening. The hotkey and the click keep working either way.
- **Monitor info** now shows whether voice is on and which speech language it uses.
- The **About** box now shows the version number.

## 1.0.0 (2026-11-02): First release

### Added
- **Tray app.** A small monitor icon near the clock. Run it on both computers.
- **One click or one hotkey to switch.** Left-click the icon or press **Ctrl + Alt + M**, and the monitor switches to the *other* computer.
- **Automatic PC / laptop detection.** It uses the Windows chassis type, with a battery check as a fallback. You can override it with `$ThisMachine`.
- **Switch to PC / Switch to Laptop** menu items, to go to a specific computer.
- **Swap PC / Laptop inputs.** A one-click fix for monitors that use the input numbers the other way round (saved).
- **Change hotkey...** lets you press any new key combination (saved). The menu shows **(OFF)** if another app already uses the hotkey.
- **Monitor info / input codes...** shows which computer this is, the hotkey status and what the monitor reports.
- **Start with Windows.** A per-user startup entry with no console window and no admin rights needed.
- **About Monitor Switch...** shows the credits and a link to the project.
- **Command line:** `-Toggle`, `-To <code>` and `-Info`, for shortcuts, macro keys or a Stream Deck.
- Settings are saved per computer in `%APPDATA%\MonitorSwitch\settings.json`.
- It talks to the monitor over the video cable (DDC/CI, VCP code `0x60`), with no extra hardware, no installer and no network access.
- Licensed under the **PolyForm Noncommercial License 1.0.0**, with required credit to the author.
