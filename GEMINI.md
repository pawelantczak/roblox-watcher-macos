# Roblox Watcher (macOS)

Roblox Watcher is a native macOS automation and monitoring suite designed to maintain 24/7 uptime for Roblox games (such as Pet Simulator 99). It detects disconnections, automatically reconnects or relaunches the client, navigates back to active event areas, and prevents idle kick timeouts.

---

## Architecture & Project Structure

- **Single Source of Truth for Versioning**:
  - `VERSION`: Root plain-text file holding the semver string (e.g. `1.1.0`).
  - Stamped into `Resources/Info.plist`, CLI banner, GUI app footer badge, and build output filenames.
- **Components**:
  - `Sources/Core/`: Shared business logic, models, services, and utilities:
    - `Models.swift`: `Config`, `Stats`, `DetectedText`, and `RobloxWindowInfo`.
    - `Classifier.swift`: OCR text filtering (`WatcherClassifier`) and `WatcherUtils`.
    - `WindowService.swift`: Window discovery, placeId parsing, and activation.
    - `VisionService.swift`: Screen capture and on-device Apple Vision OCR.
    - `InputService.swift`: Synthetic mouse events, hardware warping, and Anti-AFK engine.
    - `GameService.swift`: Game relaunching and event area navigation workflows.
    - `StorageService.swift`: Deterministic JSON persistence and version resolution.
    - `LockManager.swift`: POSIX advisory kernel lock (`flock`) engine.
    - `PowerService.swift`: IOKit `IOPMAssertion` display sleep and auto-lock prevention engine.
    - `UpdateService.swift`: Asynchronous GitHub Releases API update checker and semver engine.
  - `Sources/CLI/main.swift`: Headless CLI daemon (~170 lines) polling loop.
  - `Sources/App/`: Modular Native Cocoa GUI application:
    - `AppEntry.swift`: `@main` bootstrap and single-instance validation.
    - `AppDelegate.swift`: NSWindow lifecycle, menu bar status item, dock reopen handler.
    - `WatcherEngine.swift`: State coordination, background timers, and telemetry.
    - `DashboardBridge.swift`: Typed WebKit script message handlers (`DashboardAction`).
  - `Tests/WatcherTests.swift`: Self-contained unit test suite covering OCR text classification, Voice Chat notification filtering, config serialization, placeId parsing, Anti-AFK math, and kernel file locks.
  - `test.sh`: Standalone fast test runner compiling and running the test suite in <5ms.
  - `Resources/index.html`: Responsive dark-mode dashboard UI communicating via native WebKit script message handlers.
  - `Resources/`: App icons (`app_icon.png`), crisp menu bar indicators (`menubar_active.png`, `menubar_inactive.png`), and `Info.plist`.
  - `Package.swift`: Swift Package Manager manifest defining `RobloxWatcherCore`, CLI, App, and test targets.
  - `build.sh`: Runs `./test.sh`, builds Universal binaries (`arm64` + `x86_64`) targeting macOS 14.0+, automatically applies persistent local code signing (`RobloxWatcherDev`) or ad-hoc signing (`-`), and packages `Roblox-Watcher-v<version>.zip` via Apple native `ditto`.
  - `bump.sh`: Automated semver bumper (`patch`, `minor`, `major`, or custom version) that updates `VERSION`, synchronizes `CHANGELOG.md` headers, and runs `build.sh`.
  - `.github/workflows/build.yml`: GitHub Actions pipeline configured for `runs-on: self-hosted`, executing `./test.sh`, generating CI artifacts, extracting release notes from `CHANGELOG.md`, and publishing hybrid GitHub releases when `v*` tags are pushed.

---

## Core Capabilities

1. **Vision OCR Detection**:
   - Uses Apple's native Vision framework (`VNRecognizeTextRequest`) directly on screen captures of the Roblox window (`screencapture -l <windowId>`).
   - Detects disconnect dialogs, error codes (`277`, `279`, `267`, `271`, `268`, `273`), and server shutdown notices without window focus.
   - Filters out non-fatal notification toasts (such as "You've disconnected from Voice Chat") using configurable `ignorePhrases`.
2. **Reconnection & Teleport**:
   - Dispatches synthesized mouse events via dual-layer window activation (`NSAppleScript` + `NSRunningApplication.activate`).
   - Targets the exact center of recognized event text (or the vertical midpoint between the first line's top and last line's bottom for multi-line labels), eliminating arbitrary pixel offsets.
   - Utilizes focused 4x super-sampled scanning on the left 20% sidebar to guarantee small label detection on low-resolution windows.
   - Scans and verifies target event keywords (`pumpkin`, `tycoon`, etc.) on the left UI panel before clicking; never falls back to arbitrary hardcoded pixel coordinates.
3. **Seamless Anti-AFK Keep-Alive**:
   - Delivers a mouse click with randomized spatial jitter (`±8px`) to the Roblox window every 5 minutes using a 50ms Focus-Click-Restore sequence.
   - Momentarily focuses Roblox so `UserInputService` accepts the input to reset the 20-minute idle kick timer, then instantly restores previous application focus and returns the hardware cursor to its original position.
4. **Dock & Menu Bar Integration**:
   - Running application icon in the Dock restores the main window when clicked (`applicationShouldHandleReopen`).
   - Menu bar status item displays live watcher state and provides start/stop and window display controls.
5. **Single-Instance Enforcement**:
   - Enforces a single running instance via POSIX non-blocking kernel lock (`flock`).
   - Launching a second instance of `Roblox Watcher.app` activates the existing window and terminates immediately without creating duplicate processes.
6. **macOS Display Sleep & Auto-Lock Prevention**:
   - Manages native `IOPMAssertion` (`kIOPMAssertionTypePreventUserIdleDisplaySleep`) while the watcher is running.
   - Prevents the macOS screensaver, display dimming, and screen lock from triggering, ensuring uninterrupted Vision OCR analysis and mouse dispatch without disrupting the system when stopped.
7. **First-Run Permissions Audit & Guided Setup**:
   - Proactively audits macOS Screen Recording (`CGPreflightScreenCaptureAccess`) and Accessibility (`AXIsProcessTrusted`).
   - Surfaces a reactive warning banner with a 1-click gateway to the appropriate macOS System Settings privacy panes.
8. **Automated GitHub Release & Update Checker**:
   - Asynchronously queries GitHub Releases API (`UpdateService`) on startup and compares semver versions without blocking the UI.
   - Surfaces an animated update pill in the header (`✨ Update vX.Y.Z`) linking directly to the latest GitHub release assets.
9. **Desktop Privacy Guard & Minimized Window Recovery**:
   - Automatically restores minimized Roblox windows from the Dock via AppleScript (`unminimizeRobloxIfNeeded`).
   - Eliminates fallback to capturing the primary display, ensuring personal desktops are never scanned or leaked if Roblox is hidden.
10. **CrashReporter Auto-Dismissal**:
    - Automatically terminates lingering modal macOS `Problem Reporter` dialogs during force-relaunch to ensure uninterrupted game focus and input delivery.

---

## Strict Rules for LLMs & AI Agents

> [!IMPORTANT]
> Any AI agent, LLM, or automated assistant working on this repository must strictly adhere to the following rules:

1. **NEVER TAG CODE**:
   - Do **NOT** create, move, delete, or push Git tags (never run `git tag`, `git tag -f`, `git push origin <tag>`, or `git push --tags`).
   - Tagging is strictly reserved for the human user.
2. **ALWAYS UPDATE CHANGELOG.md**:
   - Every feature, fix, or breaking change must be documented in [CHANGELOG.md](file:///Users/krr/Sources/roblox-watcher/CHANGELOG.md) adhering to the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.
3. **ALWAYS UPDATE GEMINI.md**:
   - Any architectural change, new script, configuration field, or rule modification must be recorded in this file ([GEMINI.md](file:///Users/krr/Sources/roblox-watcher/GEMINI.md)).
4. **VERSION BUMPING DETERMINED BY CHANGELOG**:
   - Always determine semver increments strictly from the release entries in [CHANGELOG.md](file:///Users/krr/Sources/roblox-watcher/CHANGELOG.md):
     - If there are **only fixes** (`### Fixed`), bump **patch** (`x.y.Z`).
     - If there are any **new features or capabilities** (`### Added`), bump **minor** (`x.Y.0`).
     - If there are **breaking architectural changes**, bump **major** (`X.0.0`).
5. **MODULAR ARCHITECTURE & FILE BUDGET**:
   - Keep individual Swift files under 250 lines of code. Split files whenever responsibilities diverge.
   - All shared domain services, game automation, OCR, window finding, input simulation, and persistence must reside exclusively in `Sources/Core/`. Never duplicate domain logic across `Sources/App/` or `Sources/CLI/`.
   - Adhere strictly to naming conventions:
     - Core services: `<Domain>Service.swift` (e.g. `WindowService.swift`, `VisionService.swift`).
     - Models: `Models.swift`.
     - UI Controllers: `<Component>Delegate.swift` or `<Component>Bridge.swift`.

