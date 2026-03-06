# Whiplash

A macOS menu bar utility for tracking developer tasks across concurrent contexts — terminal tabs, Claude Code sessions, and more.

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

<!-- TODO: Replace with actual screenshot -->
<!-- ![Whiplash Screenshot](docs/screenshot.png) -->

## Features

- **Global Hotkey** — Press `⌥⇧T` from anywhere to instantly open Whiplash
- **Session Auto-Detection** — Automatically detects running Claude Code sessions and links tasks to context
- **Menu Bar Native** — Lightweight popover UI, no dock icon, no window management
- **CLI Companion** — Standalone Swift script shares the same task file for terminal workflows
- **Fully Local** — All data stored in `~/.whiplash.json`. No accounts, no cloud, no telemetry
- **Zero Dependencies** — Pure Swift & SwiftUI. No CocoaPods, no SPM packages, no Electron

## Install

### Direct Download

Download the latest `.app` bundle from [GitHub Releases](https://github.com/arvindang/whiplash/releases), unzip, and move to `/Applications`.

### Build from Source

Requires **Xcode 15+** and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/arvindang/whiplash.git
cd whiplash
brew install xcodegen
xcodegen generate
xcodebuild -project Whiplash.xcodeproj -scheme Whiplash
```

The built app will be in `build/Release/Whiplash.app`.

## CLI

A standalone Swift script that shares the same `~/.whiplash.json` file:

```bash
swift CLI/whiplash-cli.swift add "Fix login bug"
swift CLI/whiplash-cli.swift list
swift CLI/whiplash-cli.swift done 1
swift CLI/whiplash-cli.swift pause 2
```

## System Requirements

| Requirement | Details |
|---|---|
| **OS** | macOS 14 Sonoma or later |
| **Architecture** | Apple Silicon and Intel |
| **Disk Space** | < 5 MB |
| **Permissions** | Accessibility (optional, for global hotkey) |

## License

MIT
