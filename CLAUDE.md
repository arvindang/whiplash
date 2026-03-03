# Whiplash

macOS menu bar utility for tracking developer tasks across concurrent contexts (terminal tabs, Claude Code sessions, etc.).

## Build & Development

```bash
# Regenerate .xcodeproj from project.yml
xcodegen generate

# Build
xcodebuild -project Whiplash.xcodeproj -scheme Whiplash

# CLI (standalone Swift script, shares ~/.whiplash.json)
swift CLI/whiplash-cli.swift <command>   # commands: add, list/ls, done, pause
```

No tests exist currently.

## Architecture

- **`WhiplashApp`** (`@main`) → `AppDelegate` → `StatusBarController`
- **`StatusBarController`**: NSStatusItem + NSPopover hosting SwiftUI views
- **`TaskStore`**: `@Observable @MainActor` singleton, persists to `~/.whiplash.json`
- **`SessionScanner`**: `actor`, auto-detects Claude Code processes via pgrep + session file parsing
- **`FileWatcher`**: monitors `~/.claude/history.jsonl` via DispatchSource for immediate session detection
- **`HotKeyManager`**: global ⌥⇧T hotkey via `NSEvent.addGlobalMonitorForEvents`
- **CLI**: standalone Swift script (`CLI/whiplash-cli.swift`) sharing the same JSON file

## Swift 6 Concurrency Patterns

- `nonisolated(unsafe)` for stored properties accessed in deinit of `@MainActor` classes
- `@unchecked Sendable` for FileWatcher (wraps DispatchSource internally)
- `actor` for SessionScanner (shell commands off main thread)
- Strict concurrency is enabled (`SWIFT_STRICT_CONCURRENCY: complete`)

## Key Constraints

- **App Sandbox OFF** — needs filesystem + process access
- **Hardened Runtime ON**
- **macOS 14+** (Sonoma) deployment target
- **No external dependencies**
- **LSUIElement: true** — no dock icon, menu bar only
- **Bundle ID**: `io.embed3d.whiplash`
- **Code signing**: Sign to Run Locally (ad-hoc, `CODE_SIGN_IDENTITY: "-"`)
