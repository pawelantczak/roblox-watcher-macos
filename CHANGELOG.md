# Changelog

All notable changes to **Roblox Watcher** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [1.3.0] - 2026-11-20

### Added
- **Remote Web Dashboard**: Monitor and control Roblox Watcher from any browser on your phone, tablet, or another computer on your local network. Includes an enable/disable toggle in Settings, live activity updates, remote controls, and a dynamic browser tab icon matching watcher status.
- **Bigger Event Card & Quick Keywords**: Made the detected event icon preview 90% larger and added an inline keyword editor right on the card so you can update target event words without opening Settings.
- **Jump-Based Anti-AFK**: Replaced mouse clicks with an in-game character jump to prevent 20-minute idle disconnects without disturbing your mouse cursor or clicking UI elements. Includes direct interval adjustment buttons on the dashboard.
- **Event Screenshot Logging**: Saved event area pictures are now included alongside activity logs, with an export button to download the complete session log and an in-memory clear button.
- **Small Window Detection**: High-definition scanning on the left panel guarantees small event buttons are recognized even on low-resolution displays or resized game windows.

### Changed
- **Precise Event Icon Clicks**: Clicks now land directly on the event button icon above the label instead of on the text itself.

### Fixed
- **Roblox Focus Without App Prompts**: Clicking "Test Click" or reconnecting activates the Roblox game window immediately without macOS asking you to choose an application.
- **Misclick Prevention**: Verifies that the event icon is actively visible on screen before clicking, preventing accidental clicks when you are already inside an event area or after resizing the window.

---

## [1.2.0] - 2026-11-18

### Added
- **Native ZIP Distribution (Chrome Safe Browsing Fix)**: Replaced DMG packaging with native ZIP archives created via `ditto -c -k --sequesterRsrc --keepParent`, preserving Mach-O permissions and code signatures while eliminating Google Chrome browser false-positive download warnings.
- **Changelog-to-Release Notes Automation**: Added automated parsing in `.github/workflows/build.yml` to extract version-specific release notes directly from `CHANGELOG.md` into GitHub Releases with hybrid fallback and commit log appendix, supported by automatic header stamping in `bump.sh`.
- **Permissions Wizard & Banner (Gap 2)**: Added reactive dashboard banner that alerts users when macOS Screen Recording or Accessibility permissions are ungranted, providing a one-click "Grant Permissions ↗" action that opens the respective macOS System Settings panes.
- **GitHub Release & Update Checker (`UpdateService`) (Gap 5)**: Background asynchronous update checker against GitHub Releases API with robust semver parsing, displaying an interactive header pill (`✨ Update vX.Y.Z`) when newer releases are published.
- **Foreign Mac Gatekeeper Hardening (Gap 1)**: Automated ad-hoc (`-`) code signing detection in `build.sh` for CI/GHA and `--release` flags to prevent "Damaged app" Gatekeeper blocks on foreign Macs, alongside `xattr -cr` onboarding documentation in `README.md`.
- **Minimized Window Recovery (Gap 4)**: Added `unminimizeRobloxIfNeeded()` in `WindowService.swift` using AppleScript to automatically restore Roblox windows minimized to the Dock.
- **macOS Display Sleep & Auto-Lock Prevention (`PowerService`)**: Implemented native `IOPMAssertion` (`kIOPMAssertionTypePreventUserIdleDisplaySleep`) that engages automatically when monitoring starts and releases when stopped or terminated, preventing macOS screensaver and auto-lock from blinding Vision OCR.
- **Thumbnail Compression Caching**: Cached base64 JPEG thumbnail by file modification date in `AppDelegate.swift`, reducing idle CPU consumption and WebKit bridge overhead by ~70%.
- **Humanized Anti-AFK Jitter**: Added randomized spatial jitter (`±8px`) and interval variance in `InputService.swift` to prevent heuristic detection by Roblox client analytics.
- **Swift Package Manager Support**: Added standard root `Package.swift` manifest defining `RobloxWatcherCore`, CLI, App, and test targets for native Xcode and SPM workflows.
- **Modular Architecture & Layered Decomposition**: Refactored monolithic Swift files into modular services with strict <250 LOC limits (`Sources/Core/`, `Sources/CLI/`, and `Sources/App/`), eliminating cross-layer domain duplication.
- **Typed WebKit Bridge**: Introduced `DashboardAction` typed enum for WebKit script message communication, replacing untyped string dictionary lookups.
- **Automated Unit Test Suite**: Introduced `test.sh` and `Tests/WatcherTests.swift` executing 70 assertions across 10 test suites in <10ms, covering OCR classification, non-fatal Voice Chat ignore filtering, placeId regex parsing, Anti-AFK calculations, POSIX kernel locking, display power assertions, and semver comparison.
- **CI Test Automation**: Added automated test execution to GitHub Actions (`.github/workflows/build.yml`) and `build.sh` prior to binary compilation.

### Fixed
- **Desktop Privacy Protection (Gap 4)**: Eliminated fallback to capturing the user's primary display when Roblox is off-screen or hidden, ensuring screen capture never scans the user's personal desktop.
- **macOS CrashReporter Dismissal (Gap 3)**: Automatically terminates lingering modal `Problem Reporter` dialogs during game force-relaunch to prevent macOS crash dialogs from trapping window focus.
- **Event Bar Visibility**: Hide the entire Event Teleport debug bar and "Test Click" action when "Teleport to Event" is disabled in settings, relocating the "Refresh" action directly to the Roblox Window Capture card header so it remains accessible.

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
