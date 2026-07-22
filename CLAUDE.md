# CLAUDE.md

@AGENTS.md

This file contains only Claude Code-specific additions for this repository. Shared project guidance lives in `AGENTS.md` and must not be duplicated here.

## Project

Native macOS to-do app, SwiftUI + SwiftData with an AppKit-backed task editor, single window + menu-bar popover sharing the same model container. Bundle ID `com.insight.to-do-block`. Deployment target **macOS 15.7**, built with Xcode 26. See `AGENTS.md` for general Swift / SwiftUI / SwiftData / AppKit-interop style; this file documents project-specific behavior, hazards, and conventions that override or extend it.

The folder/target name `todo block` contains a space — always quote paths in shell commands and `xcodebuild` arguments.

## Build, test, run

```bash
# Open in Xcode
open "todo block.xcodeproj"

# Debug build (CLI)
xcodebuild -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS' build

# Run unit tests (XCTest + Swift Testing both present; skip UI test runner locally)
xcodebuild test -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:"todo blockTests"

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

**After a successful build, kill the running instance and relaunch the freshly built `.app`** so the user sees the new menu-bar binary immediately rather than the stale one still in memory:

```bash
pkill -f "todo block.app" 2>/dev/null || true
APP_PATH="$(xcodebuild -project 'todo block.xcodeproj' -scheme 'todo block' \
  -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
open "$APP_PATH/todo block.app"
```

Skip the relaunch step when the diff is docs-only (`*.md`, comments-only changes), when the user explicitly says they'll launch it themselves, or when the task only ran tests instead of a Debug build.

**Release flow**: `git tag v0.1.0 && git push origin main v0.1.0` triggers `.github/workflows/objective-c-xcode.yml`, which builds Release unsigned and uploads `Todo-Block-macOS.dmg` to the GitHub Release. See `PACKAGING.md` for manual archive/distribution.

## Architecture

### Single source of truth: `TodoStore.shared`

`TodoStore` (`todo block/Services/TodoStore.swift` + 4 extension files in same folder: `+ItemMutations`, `+Persistence`, `+DaySectionMaintenance`, `+Clipboard`) is the `@MainActor @Observable` singleton that owns **all** runtime state. The main window and menu-bar popover are bound to the same `ModelContainer` created in `todo_blockApp`, so both share `TodoStore.shared`'s in-memory caches (`todoItemsCache`, `daySectionsCache`) and stay live without any cross-window sync code.

`Services/` also holds the single current-list coordinator, each list's stable action module, selection state, operation history, and focused engines for text, hierarchy, reorder, clipboard, and drag behavior. `Models/` is reserved for `@Model` types only.

⚠️ Extension-file split note: because Swift `private(set)` doesn't cross files, the caches and internal counters on `TodoStore` (e.g. `todoItemsCache`, `refreshTrigger`, `modelContext`) are declared as plain `internal var`. This is a deliberate friendship pattern with the 4 extension files — **do not write these from view code**. If you find yourself wanting to, you almost certainly want a mutation method instead.

- Initialization is idempotent. `initialize(with:)` short-circuits when the same `ModelContext` is passed again, only reloading from the DB. Tests and `#Preview`s rely on this.
- Writes go to the cache immediately, then a 0.3 s debounced `saveTask` flushes to SwiftData. **`restoreItem` calls `flushPendingChangesSync()` first** to avoid colliding with a pending delete under the unique constraint.
- 保存失败不会撤回用户眼前的修改；应用保留最新状态、持续提示并自动重试。Logging goes through `os.Logger(subsystem: "com.insight.to-do-block", category: "persistence")`.
- `refreshTrigger` is bumped only when *membership/order* of a derived collection changes. Field-level edits (`title`, `isCompleted`, `indentLevel`) drive UI through `@Bindable item` directly — don't bump it for those.
- `daySectionsCache` is auto-pruned: every `deleteItem*` checks the parent section and removes it if empty (orphan cleanup).

### Schema (SwiftData, local only, no CloudKit)

Two `@Model` types in `todo block/Models/` (folder reserved for `@Model` types only):
- `TodoItem` — `id`, `title`, `isCompleted`, `indentLevel` (0–4), `sortOrder` (Double), `containerKindRaw` (`scheduled` / `longTermUrgent` / `longTermImportant`), `dayDate` (start-of-day).
- `DaySection` — date-keyed grouping header with editable title.

No SwiftData relationships; items belong to a section by matching `dayDate`/`containerKind`. No manual schema version tracking — every `@Model` field carries a default value, so SwiftData lightweight migration handles new fields automatically. The `TodoItem.containerKind` getter has a `?? .scheduled` fallback as a defensive layer for any pre-v2 row that might still carry an empty `containerKindRaw`.

### Undo / Redo

`TodoUndoManager` owns one structured operation history (50 steps), with no system undo stack or compatibility conversion path. The app menu's Undo/Redo (`todo_blockApp.swift`) goes only through `ActiveListCommandCoordinator`; the claimed list module resolves pending text input and the shared operation history. A stale operation is discarded as a whole and the history continues to the next complete operation; never partially apply a recorded operation.

### Menu-bar popover bridge

`MenuBarStatusItemController` (singleton) creates **one** `NSHostingController` the first time `installIfNeeded` is called and **never replaces it** (swapping `contentViewController` while the popover is shown dismisses it). Popover lifecycle is observed via `NSPopover.willShow/didCloseNotification` and rebroadcast as `.menuBarPopoverWillShow` / `.menuBarPopoverDidClose` (see `MenuBarPopoverNotifications.swift`). **Do not set `popover.delegate`** — it makes `XCUIApplication.terminate()` hang for 60 s in UI tests.

### Current-list command pattern

`TodoListView`, `LongTermListView`, and `MenuBarView` each retain one stable `TodoListActionModule`. `ActiveListCommandCoordinator.shared` is the only current-list command target: direct list interaction claims its registered module, while the menu-bar popover temporarily claims commands between `menuBarPopoverWillShow` and `menuBarPopoverDidClose`. Application commands query and execute only through this coordinator. Do not add another service that stores the current list or its scope.

### AppKit editor

The task editor lives in `Views/AppKitEditor/` and is embedded through `TodoEditorRepresentable`. `TodoListView`, `LongTermListView`, and `MenuBarView` all use this same editor; do not reintroduce a second SwiftUI task editor path.

- `TodoEditorViewController` owns the AppKit list surface, row reuse, drop indicator, and drag/selection routing.
- `TodoEditorRowView` owns row-level input: checkbox, drag handle, `NSTextView`, row focus, Space toggle, Command+Up/Down, and left-button long-press multi-select.
- `TodoListActionModule` is the boundary back into `TodoStore` and `SelectionManager`. Keep persistence, reorder, undo, clipboard, and selection rules in services rather than duplicating them in views.
- `TodoEditorTextView` preserves IME composition state. Do not handle destructive commands while `hasMarkedText()` is true.

### Drag & drop

- List-internal drag starts from `TodoEditorDragHandleView`; row-body left drag is reserved for long-press multi-select.
- Drop resolution is AppKit-based: row frames are converted inside `TodoEditorViewController`, and the final move goes through `TodoParentChildGroupMoveModule`.
- Cross-page/sidebar drag uses `TodoEditorDragSession.shared`. Sidebar targets report AppKit screen-space frames through `SidebarDropFrameReader`; editor drag events are converted to screen coordinates before hit-testing.
- Dragging to the sidebar long-term entry moves the whole parent/child block to long-term important at root indent. Dragging to a month uses that month's latest scheduled date, or the clamped fallback date when the month is empty.

### Selection

Selection state remains in `SelectionManager`. The AppKit editor supports click select, Shift-click range select, and left-button long-press drag selection. Text selection still belongs to the row `NSTextView`, so keep row-body selection behavior separate from text-view mouse handling.

### Previews

All `#Preview` blocks must go through `TodoPreviewSupport.bootstrap()`, which shares **one** in-memory `ModelContainer`. Creating per-preview containers reset the `TodoStore` singleton when Xcode Canvas ran multiple previews concurrently and crashed.

## Conventions specific to this repo

- Test target name has a space: `"todo blockTests"`. The test bundle id is legacy `insight.notion-to-doTests` — don't "fix" it. For local verification, run `-only-testing:"todo blockTests"`; launching the UI test runner can trigger macOS "app is damaged" dialogs under unsigned local builds.
- Project `SWIFT_VERSION` in pbxproj is `5.0`, but the code is written for **Swift 6** strict concurrency (per `AGENTS.md`). Treat new code as Swift 6 even though the build setting hasn't been bumped.
- Both XCTest (`TodoStoreTests`, etc.) and Swift Testing (`todo_blockTests.swift`) are present; new tests for store/engine logic follow the existing XCTest style for consistency.
- See `docs/code-review-todos.md` for the historical list of fixed perf/correctness issues — useful when a regression looks familiar.
