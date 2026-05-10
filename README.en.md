# Todo Block

[中文](README.md) | [English](README.en.md)

Todo Block is a native macOS to-do app with nested tasks, keyboard-first workflows, quick menu bar access, and date-based task organization.

## Screenshot

![Todo Block startup screen](docs/images/todo-block-startup.png)

## Features

- Native macOS experience built with SwiftUI and SwiftData
- Nested tasks with up to 4 levels of subtasks
- Keyboard-first workflow for creating, editing, and moving tasks
- Automatic date grouping with editable section titles
- Menu bar access for checking today's tasks at a glance
- Drag and drop reordering across lists and sections
- Multi-selection with `Shift + Click`
- Real-time sync between the main window and menu bar
- Undo and redo for common actions
- Long-term task buckets for backlog-style planning

## Download

- Latest release page: [GitHub Releases](https://github.com/keru-s/todo-block/releases/latest)
- Direct download: [Todo-Block-macOS.zip](https://github.com/keru-s/todo-block/releases/latest/download/Todo-Block-macOS.zip)

If macOS says the app is damaged or should be moved to the Trash, run:

```bash
xattr -dr com.apple.quarantine "/Applications/todo block.app"
```

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
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘C` | Copy task(s) |
| `⌘V` | Paste task(s) |

## Project Structure

```text
todo block/
├── Models/         # Models, persistence, undo, clipboard, and core logic
├── Views/
│   ├── Main/       # Main window UI
│   ├── Editor/     # Task editing views
│   ├── MenuBar/    # Menu bar UI
│   └── Shared/     # Shared drag and reorder logic
├── ContentView.swift
└── todo_blockApp.swift
```

## Development

### Run tests

```bash
xcodebuild test \
  -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS'
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
- SwiftData
- `@Observable`

## License

MIT
