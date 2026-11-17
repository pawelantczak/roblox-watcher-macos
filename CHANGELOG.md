# Changelog

All notable changes to **Roblox Watcher** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-11-17

### Added
- **Seamless Anti-AFK Keep-Alive**: Dispatches mouse clicks to the center of the Roblox window every 5 minutes using a 50ms Focus-Click-Restore sequence, ensuring Roblox's `UserInputService` registers the input to reset the 20-minute AFK kick timer while immediately restoring previous window focus and cursor location.
- **Anti-AFK Settings Toggle**: Added setting control in the configuration modal to enable/disable background keep-alive clicks.
- **Anti-AFK Metric Card**: Added a 5th top-row dashboard card displaying live Anti-AFK state (`ENABLED`, `DISABLED`, `PAUSED`) and real-time countdown to the next keep-alive click.
- **Log Stream Colour Coding & Smart Scroll**: Highlighted logs by category (permissions/errors: red, reconnects: yellow, anti-afk: green). Pauses auto-scroll when user scrolls up to inspect history, with a "Resume live" button to re-engage live streaming.
- **Agent Guidelines (`GEMINI.md`)**: Added repository documentation and explicit constraints prohibiting automated tagging and mandating changelog updates.

### Fixed
- **Voice Chat Disconnect Filtering**: Excluded non-fatal notification toasts such as "You've disconnected from Voice Chat" via configurable `ignorePhrases` (`voice chat`, `voice`) to prevent false-positive reconnects and restarts.

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
