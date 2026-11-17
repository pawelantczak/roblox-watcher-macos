# Roblox Watcher (macOS)

Roblox Watcher is a native macOS automation and monitoring suite designed to maintain 24/7 uptime for Roblox games (such as Pet Simulator 99). It detects disconnections, automatically reconnects or relaunches the client, navigates back to active event areas, and prevents idle kick timeouts.

---

## Architecture & Project Structure

- **Single Source of Truth for Versioning**:
  - `VERSION`: Root plain-text file holding the semver string (e.g. `1.1.0`).
  - Stamped into `Resources/Info.plist`, CLI banner, GUI app footer badge, and build output filenames.
- **Components**:
  - `Sources/main.swift`: Headless CLI daemon (`roblox-watcher-v<version>`, symlinked as `roblox-watcher`).
  - `Sources/NativeApp.swift`: Native Cocoa GUI application (`Roblox Watcher.app`) embedding a lightweight WebKit dashboard.
  - `Resources/index.html`: Responsive dark-mode dashboard UI communicating via native WebKit script message handlers.
  - `Resources/`: App icons (`app_icon.png`), crisp menu bar indicators (`menubar_active.png`, `menubar_inactive.png`), and `Info.plist`.
  - `build.sh`: Builds Universal binaries (`arm64` + `x86_64`) targeting macOS 14.0+, automatically applies persistent local code signing (`RobloxWatcherDev`) or ad-hoc signing (`-`), and packages `Roblox-Watcher-v<version>.dmg`.
  - `bump.sh`: Automated semver bumper (`patch`, `minor`, `major`, or custom version) that updates `VERSION` and runs `build.sh`.
  - `.github/workflows/build.yml`: GitHub Actions pipeline configured for `runs-on: self-hosted`, generating CI artifacts and publishing GitHub releases when `v*` tags are pushed.

---

## Core Capabilities

1. **Vision OCR Detection**:
   - Uses Apple's native Vision framework (`VNRecognizeTextRequest`) directly on screen captures of the Roblox window (`screencapture -l <windowId>`).
   - Detects disconnect dialogs, error codes (`277`, `279`, `267`, `271`, `268`, `273`), and server shutdown notices without window focus.
   - Filters out non-fatal notification toasts (such as "You've disconnected from Voice Chat") using configurable `ignorePhrases`.
2. **Reconnection & Teleport**:
   - Dispatches synthesized mouse events via dual-layer window activation (`NSAppleScript` + `NSRunningApplication.activate`).
   - Scans and verifies target event keywords (`pumpkin`, `tycoon`, etc.) on the left UI panel before clicking; never falls back to arbitrary hardcoded pixel coordinates.
3. **Seamless Anti-AFK Keep-Alive**:
   - Delivers a mouse click to the center of the Roblox window every 5 minutes using a 50ms Focus-Click-Restore sequence.
   - Momentarily focuses Roblox so `UserInputService` accepts the input to reset the 20-minute idle kick timer, then instantly restores previous application focus and returns the hardware cursor to its original position.
4. **Dock & Menu Bar Integration**:
   - Running application icon in the Dock restores the main window when clicked (`applicationShouldHandleReopen`).
   - Menu bar status item displays live watcher state and provides start/stop and window display controls.
5. **Single-Instance Enforcement**:
   - Enforces a single running instance via POSIX non-blocking kernel lock (`flock`).
   - Launching a second instance of `Roblox Watcher.app` activates the existing window and terminates immediately without creating duplicate processes.

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
