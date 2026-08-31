# Architecture

## Single source of truth: `TodoStore.shared`

`TodoStore`（`todo block/Services/TodoStore.swift` + 同目录 6 个扩展文件：`+ItemMutations`、`+Persistence`、`+DaySectionMaintenance`、`+Clipboard`、`+CarryOver`、`+UITestSeeding`）是 `@MainActor @Observable` 单例，拥有**全部**运行期状态。主窗口和菜单栏 popover 绑定 `todo_blockApp` 创建的同一个 `ModelContainer`，共享 `TodoStore.shared` 的内存缓存（`todoItemsCache`、`daySectionsCache`），无需跨窗口同步代码。

`Services/` 还持有唯一当前列表协调器、各列表的稳定 action module、选择状态、操作历史，以及文本、层级、重排、剪贴板、拖拽等聚焦引擎。

⚠️ Extension-file split note: because Swift `private(set)` doesn't cross files, the caches and internal counters on `TodoStore` (e.g. `todoItemsCache`, `refreshTrigger`, `modelContext`) are declared as plain `internal var`. This is a deliberate friendship pattern with the 6 extension files plus the backup services — `TodoBackupImportApplier` and `TodoBackupExactRestorer` also rewrite `todoItemsCache` / `daySectionsCache` during full-backup import and exact restore, and `TodoStore+UITestSeeding` writes them only in `-UITestSeedContent` test mode — **do not write these from view code**. If you find yourself wanting to, you almost certainly want a mutation method instead.

- Initialization is idempotent. `initialize(with:)` short-circuits when the same `ModelContext` is passed again, only reloading from the DB. Tests and `#Preview`s rely on this.
- Writes go to the cache immediately, then a 0.3 s debounced `saveTask` flushes to SwiftData. **`restoreItem` calls `flushPendingChangesSync()` first** to avoid colliding with a pending delete under the unique constraint.
- 保存失败不会撤回用户眼前的修改；应用保留最新状态、持续提示并自动重试。Logging goes through `os.Logger(subsystem: "com.insight.to-do-block", category: "persistence")`.
- `refreshTrigger` is bumped only when *membership/order* of a derived collection changes. Field-level edits (`title`, `isCompleted`, `indentLevel`) drive UI through `@Bindable item` directly — don't bump it for those.
- `daySectionsCache` is auto-pruned: every `deleteItem*` checks the parent section and removes it if empty (orphan cleanup).

## Undo / Redo

`TodoUndoManager` owns one structured operation history (50 steps), with no system undo stack or compatibility conversion path. The app menu's Undo/Redo (`todo_blockApp.swift`) goes only through `ActiveListCommandCoordinator`; the claimed list module resolves pending text input and the shared operation history. A stale operation is discarded as a whole and the history continues to the next complete operation; never partially apply a recorded operation.

## Current-list command pattern

`TodoListView`、`LongTermListView` 和 `MenuBarView` 各持有一个稳定的 `TodoListActionModule`。`ActiveListCommandCoordinator.shared` 是唯一的当前列表命令入口：列表内直接交互由已注册 module 接管；菜单栏 popover 在 `menuBarPopoverWillShow` 到 `menuBarPopoverDidClose` 之间临时接管。应用级命令只通过这个协调器查询和执行。不要再新增任何存储当前列表或其范围的服务。

## Drag & drop

- List-internal drag starts from `TodoEditorDragHandleView`; row-body left drag is reserved for long-press multi-select.
- Drop resolution is AppKit-based: row frames are converted inside `TodoEditorViewController`, and the final move goes through `TodoParentChildGroupMoveModule`.
- Cross-page/sidebar drag uses `TodoEditorDragSession.shared`. Sidebar targets report AppKit screen-space frames through `SidebarDropFrameReader`; editor drag events are converted to screen coordinates before hit-testing.
- Dragging to the sidebar long-term entry moves the whole parent/child block to long-term important at root indent. Dragging to a month uses that month's latest scheduled date, or the clamped fallback date when the month is empty.

## Selection

Selection state remains in `SelectionManager`. The AppKit editor supports click select, Shift-click range select, and left-button long-press drag selection. Text selection still belongs to the row `NSTextView`, so keep row-body selection behavior separate from text-view mouse handling.
