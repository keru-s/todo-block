# Todo Block

A native macOS to-do application built with SwiftUI and SwiftData, featuring Notion-style nested tasks, keyboard-first navigation, and real-time menu bar access.

## Features

- **Native macOS Experience** — Built with SwiftUI and SwiftData for optimal performance and system integration
- **Nested Tasks** — Support up to 4 levels of subtasks with Tab/Shift+Tab indentation
- **Keyboard-First Navigation** — Full keyboard support for creating, editing, and navigating tasks
- **Date Grouping** — Tasks automatically grouped by date with editable section titles
- **Menu Bar Widget** — Quick access to today's tasks without switching windows
- **Drag & Drop** — Intuitive task reordering within and across sections
- **Multi-Selection** — Range selection with Shift+Click for batch operations
- **Real-Time Sync** — Changes in menu bar instantly sync to main window
- **Undo/Redo** — Full undo/redo support for all operations
- **Long-term Tasks** — Eisenhower Matrix-style buckets for urgent and important tasks

## Requirements

- macOS 14.0 or later
- Xcode 16.0 or later (for development)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/yourusername/todo-block.git
cd todo-block

# Open in Xcode
open "todo block.xcodeproj"

# Build and run (⌘R)
```

### Build via Command Line

```bash
xcodebuild -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS' \
  build
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Create new task below current |
| `Backspace` | Delete empty task |
| `Tab` | Increase indent level |
| `Shift+Tab` | Decrease indent level |
| `↑` / `↓` | Navigate between tasks |
| `⌘↑` / `⌘↓` | Move task up/down |
| `Space` | Toggle completion (when checkbox focused) |
| `Shift+Click` | Multi-select range |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘C` | Copy task(s) |
| `⌘V` | Paste task(s) |

## Architecture

Todo Block uses a **single source of truth** architecture with in-memory caching for optimal performance:

```
┌─────────────────┐     ┌─────────────────┐
│   Main Window   │     │   Menu Bar      │
│   (TodoListView)│     │   (MenuBarView) │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │ @Observable
             ┌───────▼───────┐
             │   TodoStore   │  ← Singleton, in-memory cache
             │  (Observable) │
             └───────┬───────┘
                     │ Async persistence
             ┌───────▼───────┐
             │   SwiftData   │
             └───────────────┘
```

### Key Design Decisions

1. **In-Memory Cache** — `TodoStore` maintains an in-memory cache indexed by UUID for O(1) access, eliminating index-out-of-bounds errors during rapid operations

2. **Async Persistence** — All mutations update the cache immediately for instant UI response, then persist asynchronously with debouncing

3. **Component Reuse** — `TodoItemView` is shared between main window and menu bar, ensuring consistent behavior and reducing code duplication

4. **Observable Pattern** — Using `@Observable` (Swift 5.9+) for automatic UI updates without `ObservableObject` boilerplate

## Project Structure

```
todo block/
├── Models/
│   ├── TodoItem.swift           # Task model with SwiftData
│   ├── DaySection.swift         # Date grouping model
│   ├── TodoStore.swift          # Singleton data store
│   ├── UndoManager.swift        # Undo/redo support
│   ├── SelectionManager.swift   # Multi-selection state
│   ├── TodoClipboardManager.swift
│   └── MarkdownTodoCodec.swift  # Import/export support
├── Views/
│   ├── Main/
│   │   ├── SidebarView.swift    # Month sidebar
│   │   ├── TodoListView.swift   # Main task list
│   │   └── LongTermListView.swift
│   ├── Editor/
│   │   ├── DaySectionView.swift # Date section header
│   │   ├── TodoItemView.swift   # Task row (shared component)
│   │   └── CustomTextEditor.swift
│   ├── MenuBar/
│   │   └── MenuBarView.swift    # Menu bar popup
│   └── Shared/
│       ├── TodoDragCoordinator.swift
│       └── TodoDropDelegate.swift
├── todo_blockApp.swift          # App entry point
└── ContentView.swift            # Root view
```

## Tech Stack

- **Language**: Swift 6.2
- **UI Framework**: SwiftUI with `@Observable` macro
- **Persistence**: SwiftData with async autosave
- **Minimum Target**: macOS 14.0
- **Architecture**: MVVM with singleton store

## Development

### Running Tests

```bash
xcodebuild test \
  -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS'
```

### Code Style

This project follows:
- Swift concurrency best practices with strict concurrency checking
- SwiftUI patterns with `@Observable` instead of `ObservableObject`
- macOS Human Interface Guidelines for native look and feel

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Inspired by [Notion](https://notion.so)'s task management interface and keyboard-centric design philosophy.
