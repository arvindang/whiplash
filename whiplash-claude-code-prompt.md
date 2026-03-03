# Whiplash — Claude Code CLI Kickoff Prompt

## The Prompt

Copy and paste this into Claude Code CLI:

---

```
Create a macOS menu bar utility app called "Whiplash" as a Swift Package / Xcode project.

## What it does
Whiplash is a lightweight menu bar app that helps developers track what they're working on across multiple concurrent contexts (terminal tabs, Claude Code CLI sessions, Cowork, etc). It lives in the macOS status bar and shows a popover with all active tasks at a glance.

## Tech stack (ensure we're on the most current version, but are backwards compatible)
- Apple Swift version 6.2.3, SwiftUI, macOS 14+ (Sonoma)
- AppKit for NSStatusItem (menu bar)
- SwiftUI for the popover content
- No external dependencies for v1

## Project structure
Whiplash/
├── Whiplash.xcodeproj
├── Whiplash/
│   ├── WhiplashApp.swift          # @main, MenuBarExtra-based app (no dock icon)
│   ├── StatusBarController.swift   # NSStatusItem setup, popover management
│   ├── TaskListView.swift          # Main SwiftUI popover view
│   ├── TaskRowView.swift           # Individual task row component
│   ├── AddTaskView.swift           # Quick-add inline form
│   ├── Models/
│   │   ├── Task.swift              # Task model (id, title, context, status, timestamp)
│   │   └── TaskStore.swift         # ObservableObject, reads/writes ~/.whiplash.json
│   ├── Services/
│   │   ├── FileWatcher.swift       # Watches ~/.whiplash.json for external changes
│   │   └── ProcessScanner.swift    # Scans for running claude processes via Process()
│   ├── Utilities/
│   │   ├── HotKeyManager.swift     # Global hotkey (⌥⇧T) to toggle popover
│   │   └── TimeFormatter.swift     # Relative time display ("3m ago", "1h ago")
│   └── Assets.xcassets             # App icon (use bolt/lightning emoji as placeholder)
├── CLI/
│   └── whiplash-cli.swift          # Tiny companion CLI: `whiplash add "task name" --context "iTerm"`
└── README.md

## Task model
```swift
struct WhiplashTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var context: String          // e.g. "iTerm Tab 2", "Claude Code", "Cowork"
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    
    enum TaskStatus: String, Codable {
        case active
        case paused
        case done
    }
}
```

## Key behaviors

1. **Menu bar presence**: Show a small icon (⚡) in the menu bar. Clicking it opens a SwiftUI popover (NOT a dropdown menu). No dock icon — use LSUIElement or MenuBarExtra.

2. **Popover UI**:
   - Header: "Whiplash" title + task count badge
   - List of active tasks, each showing: title, context tag (colored pill), relative time since last update
   - Inline "+" button to quick-add a task (title + context dropdown)
   - Swipe left to mark done, swipe right to pause/resume
   - "Done" tasks auto-hide after 5 minutes
   - Footer: "Quit" button

3. **Data persistence**: Read/write to ~/.whiplash.json. Use FileWatcher (DispatchSource or FSEvents) to pick up external edits from the CLI tool.

4. **Global hotkey**: ⌥⇧T toggles the popover open/closed. Use CGEvent tap or NSEvent.addGlobalMonitorForEvents.

5. **Process scanning** (v1 stretch): On a 30-second timer, scan for running `claude` processes using Process("/bin/ps"). Extract their cwd and show as auto-detected tasks with context "Claude Code". User can dismiss auto-detected tasks.

6. **CLI companion**: A simple Swift script that reads/writes ~/.whiplash.json so the user can do:
   - `whiplash add "SCORM migration" --context "iTerm"`
   - `whiplash list`
   - `whiplash done <id-prefix>`

## Design notes
- Dark popover background, slightly translucent (NSVisualEffectView vibrancy)
- Compact rows — this should feel like a quick glance, not a project manager
- Context tags as small colored pills: blue for "iTerm", purple for "Claude Code", orange for "Cowork", gray for custom
- Monospace font for task titles (SF Mono or system monospaced)
- Keep the popover narrow (~320px) and tall-ish (~400px max, scrollable)

## Build settings
- macOS deployment target: 14.0
- App Sandbox: OFF (needs filesystem access for ~/.whiplash.json and process scanning)
- Hardened Runtime: ON
- LSUIElement: true in Info.plist (no dock icon)
- Bundle identifier: io.embed3d.whiplash
- Code signing: Sign to Run Locally

Start by creating the Xcode project and all files with working implementations. The app should compile and run immediately showing the menu bar icon and an empty task list popover.
```

---

## After initial scaffold, follow up with:

```
Now add a shell alias installer — create a script at Whiplash/Scripts/install-cli.sh that:
1. Compiles the CLI/whiplash-cli.swift to ~/.local/bin/whiplash
2. Echoes a shell alias suggestion for .zshrc
3. Makes the binary executable
```

## Future iterations to prompt for:

- **v1.1**: iTerm2 AppleScript integration — query active sessions and auto-populate tasks
- **v1.2**: Auto-detect git branch from cwd of running processes, show as subtitle
- **v1.3**: Notification when a background claude process finishes (exit code detection)
- **v1.4**: Raycast extension that mirrors the task list
