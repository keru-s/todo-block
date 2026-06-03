# Todo Block

[中文](README.md) | [English](README.en.md)

Todo Block is a native macOS to-do app with nested tasks, keyboard-first workflows, quick menu bar access, and date-based task organization.

## Screenshot

![Todo Block startup screen](docs/images/todo-block-startup.png)

## Features

- Native macOS experience with a SwiftUI shell, AppKit editor, and SwiftData local storage
- Nested tasks with up to 4 levels of subtasks
- Keyboard-first workflow for creating, editing, and moving tasks
- Automatic date grouping with editable section titles
- Menu bar access for checking today's tasks at a glance
- Drag and drop reordering across lists and sections
- Multi-selection with `Shift + Click` and left-button long-press drag
- Real-time sync between the main window and menu bar
- Undo and redo for common actions
- Long-term task buckets for backlog-style planning

## Download

- Latest release page: [GitHub Releases](https://github.com/keru-s/todo-block/releases/latest)
- Direct download: [Todo-Block-macOS.zip](https://github.com/keru-s/todo-block/releases/latest/download/Todo-Block-macOS.zip)

### Gatekeeper will block the first launch

Releases are **ad-hoc signed** (no paid Apple Developer ID and no notarization), so the first launch triggers an "unidentified developer" or "app is damaged" warning. It has no effect on functionality or data. Use any of the workarounds below:

**Option A (recommended)** — remove the browser-applied quarantine attribute in Terminal, then double-click as usual:

```bash
xattr -dr com.apple.quarantine "/Applications/todo block.app"
```

**Option B** — in Applications, **right-click** (or Control-click) `todo block.app` → choose Open → click Open in the confirmation dialog. The system remembers the choice for future launches.

**Option C** — after the first blocked attempt, open System Settings → Privacy & Security, scroll to the "todo block was blocked" entry, and click "Open Anyway".

## Requirements

- OS: macOS 15.7 or later
- Development: Xcode 26.0 or later

## Install and Run

### Install the app

1. Download the archive from Releases.
2. Unzip it and move `todo block.app` to the Applications folder.
3. If macOS blocks the app on first launch, run the command above and open it again.

### Run from source

```bash
git clone https://github.com/keru-s/todo-block.git
cd todo-block
open "todo block.xcodeproj"
```

Then build and run it in Xcode.

### Build from the command line

```bash
xcodebuild -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS' \
  build
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Create a new task below the current one |
| `Backspace` | Delete an empty task |
| `Tab` | Increase indent |
| `Shift+Tab` | Decrease indent |
| `↑` / `↓` | Move between tasks |
| `⌘↑` / `⌘↓` | Move a task up or down |
| `Space` | Toggle completion |
| `Shift+Click` | Range select |
| Left-button long-press drag | Continuous multi-select |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘C` | Copy task(s) |
| `⌘V` | Paste task(s) |

## Project Structure

```text
todo block/
├── Models/         # Data models
├── Services/       # Persistence, undo, clipboard, reorder, selection, and core logic
├── Views/
│   ├── AppKitEditor/ # Task editor
│   ├── Main/       # Main window UI
│   ├── MenuBar/    # Menu bar UI
│   └── Shared/     # Shared styling and preview support
└── todo_blockApp.swift
```

## Development

### Run tests

```bash
xcodebuild test \
  -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:"todo blockTests"
```

### Create a release build

Release packaging is triggered by pushing a tag that starts with `v`, for example:

```bash
git tag v0.1.0
git push origin main v0.1.0
```

The GitHub Action builds the Release app, creates `Todo-Block-macOS.zip`, and attaches it to the GitHub Release page.

If you only want to test the packaging flow, you can also run the workflow manually in GitHub Actions. Manual runs upload a build artifact but do not create a formal Release.

## Tech Stack

- Swift 6.2
- SwiftUI
- AppKit
- SwiftData
- `@Observable`

## License

MIT
