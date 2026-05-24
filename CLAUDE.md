# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native macOS to-do app, SwiftUI + SwiftData, single window + menu-bar popover sharing the same model container. Bundle ID `com.insight.to-do-block`. Deployment target **macOS 15.7**, built with Xcode 26. See `AGENTS.md` for general Swift / SwiftUI / SwiftData / AppKit-interop style; this file documents project-specific behavior, hazards, and conventions that override or extend it.

The folder/target name `todo block` contains a space — always quote paths in shell commands and `xcodebuild` arguments.

## Build, test, run

```bash
# Open in Xcode
open "todo block.xcodeproj"

# Debug build (CLI)
xcodebuild -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS' build

# Run the full test suite (XCTest + Swift Testing both present)
xcodebuild test -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS'

# Run a single XCTest method
xcodebuild test -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS' \
  -only-testing:"todo blockTests/TodoStoreTests/testRestoreInDebounceWindowDoesNotConflict"

# Unsigned Release build (matches CI; produces .app under DerivedData/Build/Products/Release/)
xcodebuild build -project "todo block.xcodeproj" -scheme "todo block" \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

`Config/NoSigning.Debug.xcconfig` disables signing for local Debug builds. `buildServer.json` wires `xcode-build-server` for SourceKit-LSP — install with `brew install xcode-build-server` if editing outside Xcode.

**After every code change, automatically run the Debug build above so the user can immediately test the latest binary** — don't wait to be asked. If the build fails, fix it before declaring the task done.

**Release flow**: `git tag v0.1.0 && git push origin main v0.1.0` triggers `.github/workflows/objective-c-xcode.yml`, which builds Release unsigned and uploads `Todo-Block-macOS.zip` to the GitHub Release. See `PACKAGING.md` for manual archive/distribution.

## Architecture

### Single source of truth: `TodoStore.shared`

`TodoStore` (`todo block/Models/TodoStore.swift`) is the `@MainActor @Observable` singleton that owns **all** runtime state. The main window and menu-bar popover are bound to the same `ModelContainer` created in `todo_blockApp`, so both share `TodoStore.shared`'s in-memory caches (`todoItemsCache`, `daySectionsCache`) and stay live without any cross-window sync code.

- Initialization is idempotent. `initialize(with:)` short-circuits when the same `ModelContext` is passed again, only reloading from the DB. Tests and `#Preview`s rely on this.
- Writes go to the cache immediately, then a 0.3 s debounced `saveTask` flushes to SwiftData. **`restoreItem` calls `flushPendingChangesSync()` first** to avoid colliding with a pending delete under the unique constraint.
- `performSave` on failure calls `modelContext.rollback()` and exposes `lastSaveError` (observable). Logging goes through `os.Logger(subsystem: "com.insight.to-do-block", category: "persistence")`.
- `refreshTrigger` is bumped only when *membership/order* of a derived collection changes. Field-level edits (`title`, `isCompleted`, `indentLevel`) drive UI through `@Bindable item` directly — don't bump it for those.
- `daySectionsCache` is auto-pruned: every `deleteItem*` checks the parent section and removes it if empty (orphan cleanup).

### Schema (SwiftData, local only, no CloudKit)

Two `@Model` types in `todo block/Models/`:
- `TodoItem` — `id`, `title`, `isCompleted`, `indentLevel` (0–4), `sortOrder` (Double), `containerKindRaw` (`scheduled` / `longTermUrgent` / `longTermImportant`), `dayDate` (start-of-day).
- `DaySection` — date-keyed grouping header with editable title.

No SwiftData relationships; items belong to a section by matching `dayDate`/`containerKind`. Schema version is tracked manually via `TodoModelContainerFactory.currentModelVersion` and `UserDefaults` key `todo.block.schema.version`; bump and add a migration when changing the schema.

### Undo / Redo

`TodoUndoManager` wraps a single `NSUndoManager` (50 steps). The app menu's Undo/Redo (`todo_blockApp.swift`) first tries the focused `NSTextView`'s undo manager, then falls back to `TodoStore.shared.undo()`. All `register*` paths use `skipStaleUndo()` so that if a registered closure's target item is gone, the chain advances rather than dead-ending. Batch delete uses self-referential undo+redo registration — keep them symmetric.

### Menu-bar popover bridge

`MenuBarStatusItemController` (singleton) creates **one** `NSHostingController` the first time `installIfNeeded` is called and **never replaces it** (swapping `contentViewController` while the popover is shown dismisses it). Popover lifecycle is observed via `NSPopover.willShow/didCloseNotification` and rebroadcast as `.menuBarPopoverWillShow` / `.menuBarPopoverDidClose` (see `MenuBarPopoverNotifications.swift`). **Do not set `popover.delegate`** — it makes `XCUIApplication.terminate()` hang for 60 s in UI tests.

### Active-context handler pattern

`TodoClipboardManager.shared` and `TodoReorderCommandManager.shared` hold closures to the currently-active list. The active list view rebinds its context on appear *and* on `menuBarPopoverWillShow` / `menuBarPopoverDidClose` so that Cmd+C / Cmd+↑↓ always target the visually-focused list. When adding new global commands, follow the same activate/clear pattern rather than introducing per-view singletons.

### Inline editor (delicate)

`CustomTextEditor` is an `NSViewRepresentable` wrapping `CustomNSTextView`. Two hard-won invariants:
1. `setFrameSize` only calls `invalidateIntrinsicContentSize` when **width** changes. Height changes are already covered by `didChangeText()`; re-invalidating on height churn forms a feedback loop with SwiftUI's `sizeThatFits` → 100% CPU hang.
2. Lists embedding this editor use plain `VStack`, **not** `LazyVStack`. The combination of `LazyVStack` prefetch + `intrinsicContentSize` measurement produces a non-converging `LazyLayoutViewCache.signalPrefetch` loop. Eager rendering of ~300 items is acceptable.

### Drag & drop

- `DropFrameTracker` (in `TodoListSharedViews.swift`) is a **reference type** holding `[UUID: CGRect]`. Writes don't invalidate SwiftUI, breaking the GeometryReader → `@State` → body cycle. Don't migrate it to `@State` of a value type.
- Per-item `GeometryReader` for frame collection is mounted unconditionally (publishes into `DropFrameTracker.itemFrames` via preference). `OptionDragSelectionMonitor` needs frames available the instant the user presses Option+left-click, so we can't gate on `coordinator.isDragging` anymore. The feedback-loop risk is contained because `DropFrameTracker` is a reference type — writes don't invalidate SwiftUI.
- `TodoDragCoordinator.shared` carries global drag location; `ContentView` renders the drag preview as a top-level overlay so it can cross list boundaries.

### Option-drag selection

`OptionDragSelectionMonitor.shared` (`Views/Shared/OptionDragSelectionMonitor.swift`) is a singleton that installs a single `NSEvent.addLocalMonitorForEvents` watching `.leftMouseDown/.leftMouseDragged/.leftMouseUp`. Without `.option` held it returns the event untouched (NSTextView gets text-selection as normal). With Option held and the hit point inside a registered list's global frame, it swallows the event chain, drives `SelectionManager.beginDragSelection / updateDragSelection / endDragSelection`, and converts AppKit window coords (bottom-left origin) to SwiftUI global coords (top-left origin) via `contentView.bounds.height - y`. Lists register/unregister in `.onAppear`/`.onDisappear` keyed by their `dropCoordinateSpaceName`. **Shift+click range-select is a separate path** (NSTextView's own `mouseDown:` reads `event.modifierFlags.contains(.shift)` and calls `SelectionManager.handleSelect(shiftPressed:)`) — don't conflate the two.

### Previews

All `#Preview` blocks must go through `TodoPreviewSupport.bootstrap()`, which shares **one** in-memory `ModelContainer`. Creating per-preview containers reset the `TodoStore` singleton when Xcode Canvas ran multiple previews concurrently and crashed.

## Conventions specific to this repo

- Test target name has a space: `"todo blockTests"`. The test bundle id is legacy `insight.notion-to-doTests` — don't "fix" it.
- Project `SWIFT_VERSION` in pbxproj is `5.0`, but the code is written for **Swift 6** strict concurrency (per `AGENTS.md`). Treat new code as Swift 6 even though the build setting hasn't been bumped.
- Both XCTest (`TodoStoreTests`, etc.) and Swift Testing (`todo_blockTests.swift`) are present; new tests for store/engine logic follow the existing XCTest style for consistency.
- See `docs/code-review-todos.md` for the historical list of fixed perf/correctness issues — useful when a regression looks familiar.
