# Changelog

All notable changes to **Roblox Watcher** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.3] - 2026-11-17

### Fixed
- **Anti-AFK Focus Synchronization**: Replaced fixed 60ms delay with active focus confirmation (`robloxApp.isActive`) and a two-click sequence (1st click confirms active AppKit window, 2nd click registers in `UserInputService` with 100ms frame dwell), preventing window activation from eating the keep-alive input.

---

## [1.1.2] - 2026-11-17

### Fixed
- **Self-Signed Identity Detection**: Removed the `-v` filter in `build.sh` so `security find-identity` detects self-signed development certificates (`RobloxWatcherDev`), enabling persistent code signing and preserving macOS permissions across rebuilds.

---

## [1.1.1] - 2026-11-17

### Added
- **Single-Instance Enforcement**: Utilizes kernel-level file locks (`flock`) to restrict execution to a single app instance. Re-opening `Roblox Watcher.app` activates and focuses the running window instead of creating duplicate processes.
- **Log Stream Colour Coding & Smart Scroll**: Highlighted logs by category (permissions/errors: red, reconnects: yellow, anti-afk: green). Pauses auto-scroll when user scrolls up to inspect history, with a "Resume live" button to re-engage live streaming.
- **Anti-AFK Metric Card**: Added a 5th top-row dashboard card displaying live Anti-AFK state (`ENABLED`, `DISABLED`, `PAUSED`) and real-time countdown, positioned directly after Watcher Status.
- **Persistent Self-Signed Identity Detection**: Configured `build.sh` to automatically sign with a free local self-signed certificate (`RobloxWatcherDev`) when present, preserving macOS Accessibility and Screen Recording permissions across new builds.

### Fixed
- **Voice Chat Disconnect Filtering**: Excluded non-fatal notification toasts such as "You've disconnected from Voice Chat" via configurable `ignorePhrases` (`voice chat`, `voice`) to prevent false-positive reconnects and restarts.
- **Reliable Anti-AFK Execution**: Upgraded background keep-alive to a 50ms Focus-Click-Restore sequence so Roblox's `UserInputService` registers the click and resets the 20-minute idle timer.

---

## [1.1.0] - 2026-11-17

### Added
- **Seamless Anti-AFK Keep-Alive**: Background keep-alive engine with 5-minute interval to maintain active Roblox sessions.
- **Anti-AFK Settings Toggle**: Added setting control in the configuration modal to enable/disable background keep-alive clicks.
- **Agent Guidelines (`GEMINI.md`)**: Added repository documentation and explicit constraints prohibiting automated tagging and mandating changelog updates.

---

## [1.0.1] - 2026-11-17

### Added
- **Universal 2 Binaries**: Compiles native code for both Apple Silicon (`arm64`) and Intel (`x86_64`) targeting macOS 14.0+.
- **Ad-Hoc Code Signing**: Added bundle code signing in `build.sh` to prevent Gatekeeper "version not supported" blocks on downloaded DMGs.
- **Versioned CLI Release Binaries**: Standalone CLI artifacts are now named `roblox-watcher-v<version>`.
- **Dock Reopen Handler**: Clicking the running app icon in the macOS Dock now restores and focuses the hidden window.
- **Startup Permission Prompts**: Proactively verifies and prompts for macOS Accessibility and Screen Recording permissions on launch and before test clicks.
- **Dynamic Event Keyword Display**: UI scanning labels now bind dynamically to the configured event keywords (`Searching left panel for [keywords] icon...`).

### Fixed
- **Instant Test Click**: Replaced 12-second delayed OCR loop with an immediate one-shot scan; removed hardcoded pixel fallbacks so clicks only dispatch when the target is verified by OCR.
- **Window Activation Reliability**: Upgraded `activateRoblox()` to use dual-layer activation via AppleScript and `NSRunningApplication.activate`.
- **Menu Bar Icon Framing**: Removed extra squircle borders and outer rings, leaving only the clean eye graphic with hollow Roblox pupil.
- **CI Runner Image**: Switched GitHub Actions runner from deprecated `macos-14` tag to `macos-latest`.

---

## [1.0.0] - 2026-11-17

### Added
- Initial release of Roblox Watcher macOS suite.
- Native macOS App (`Roblox Watcher.app`) with dark theme dashboard and embedded WebKit UI.
- Standalone Headless CLI (`roblox-watcher`).
- Real-time on-device OCR using Apple's Vision framework (`VNRecognizeTextRequest`).
- Automated reconnect button detection and synthetic click dispatch.
- Event auto-navigation and teleport clicks for Pet Simulator 99 events.
- Top Menu Bar status item with active/inactive state indicators.
- Automated DMG packaging and GitHub Actions CI workflow.
