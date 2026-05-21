# Code Review 待办清单

记录于 2026-05-21 一次完整代码审查与卡死修复后的全部发现。已修复项保留作为参考,未修复项按优先级排列。

## 已修复（2026-05-21）

| # | 严重度 | 问题 | 修复方式 | Commit |
|---|---|---|---|---|
| 1 | 致命 | `restoreItem` 在 debounce 保存窗口期内执行,可能与尚未落盘的 pending delete 撞 unique 约束 | `flushPendingChangesSync()` 在 restoreItem 头部强制落盘 | `3c961aa` |
| 2 | 致命 | `performSave` 失败时未 rollback,半保存状态污染下次会话 | rollback + `os.Logger` + 暴露 `lastSaveError` observable | `3c961aa` |
| 3 | 致命 | `UndoManager` 7 处 register 失效分支(undo 目标已删等)直接中断撤销链 | 统一改用 `skipStaleUndo()` helper,自动跳到下一可执行步骤 | `3c961aa` |
| 7 | 高 | `registerDeleteItems`(批量删除)没有 redo,与单条删除不对称 | 改为 self-referential undo+redo,重做后再注册撤销 | `3c961aa` |
| — | 致命(性能) | `CustomNSTextView.setFrameSize` 无条件 `invalidateIntrinsicContentSize` 形成自反循环,卡死时 100% CPU + 1.4 GB 物理内存 | 仅在宽度变化时 invalidate,高度变化由 `didChangeText()` 自带覆盖 | `d39350b` |
| — | 防御性 | DaySection / LongTermBucket / MenuBar 中 `@State [UUID:CGRect]` 拖放 frame 缓存有 GeometryReader→@State→body 层级反馈环风险 | 引入 `DropFrameTracker` 引用类型,frame 写入不再驱动 SwiftUI invalidation | `d39350b` |

> 已加 3 个回归测试: `testRestoreInDebounceWindowDoesNotConflict`、`testStaleUndoSkipsToNextStep`、`testBatchDeleteSupportsRedo`。

---

## 未修复 — 高优先级

### #4 拖放系统的 GeometryReader+@State 反馈环根治

**位置**: `Views/Editor/DaySectionView.swift`、`Views/Main/LongTermBucketView.swift`、`Views/MenuBar/MenuBarView.swift`

**当前状态**: 已通过 `DropFrameTracker` 把 frame 写入从 SwiftUI 观察链路上拿走(防御性修复),消除了一类反馈环。但底层架构仍是"全程挂载 GeometryReader 收集所有 item frame",平时不拖动也在做无谓测量。

**目标**: 改成**仅在拖动时**收集 frame,即:
- `coordinator.isDragging` 为 false 时不挂载 frame-collecting GeometryReader
- 拖动开始时一次性测量所有 item 的当前 frame,写入 coordinator
- 拖动过程中如布局变化(很少发生)再增量更新

**收益**: 平时(99% 的时间)零 GeometryReader 开销,内存占用更低,对未来 SwiftUI 行为变化更鲁棒。

**改动量**: 中等。3 个 view 文件 + 可能需要在 `TodoDragCoordinator` 上加 frame 缓存。

---

### #5 `bindContextsIfNeeded()` 频繁调用,跨窗口作用域错乱

**位置**: `Views/Main/TodoListView.swift`、`Views/Main/LongTermListView.swift`、`Views/MenuBar/MenuBarView.swift`

**问题**: 每个列表 view 在 `onAppear` + 多个 `onChange` 回调里反复调用 `TodoClipboardManager.shared.activateListContext(...)` 和 `TodoReorderCommandManager.shared.activateListContext(...)`。这两个 manager 是单例,activate 会切换 active scope。

**风险**:
- 当用户在主窗口和菜单栏 popover 之间快速切换时,active scope 可能错位
- 复制/粘贴或键盘重排可能落到非预期的列表上
- 多窗口场景(若将来支持)行为更不可预测

**目标**: 让 active context 由"用户最后聚焦的窗口/列表"单点决定,而不是每个 view 各自抢着 activate。

**改动量**: 中。需要重新设计 manager 的 active context 切换协议。

---

### #6 菜单栏 hosting 反复重建 + popover 闪退风险

**位置**: `MenuBarView` 相关 + `todo_blockApp.swift` 的 `MenuBarExtra` 集成

**问题**: 菜单栏 popover 每次显示时,`NSPopover.contentViewController` 被替换为新的 `NSHostingController`,旧的 controller 持有的 SwiftUI 视图层 + closure 引用未必立即释放。如果 popover 正在显示中切换 contentViewController,在 macOS 上有概率立即关闭 popover。

**目标**:
- 菜单栏 hosting controller 复用一份,内部状态用 SwiftUI 自身的 binding 驱动
- 避免在 popover 显示期间替换 contentViewController

**改动量**: 中,涉及 AppKit↔SwiftUI 桥接代码。

---

## 未修复 — 中优先级

### #8 孤儿 `DaySection` 不会被清理

**位置**: `Models/TodoStore.swift`

**问题**: 删除某日最后一项 todo 时,对应的 `DaySection` 不会被回收(没有 `@Relationship` cascade 也没有清理逻辑)。`sections(year:month:)` 和 `availableMonths()` 会一直返回空白日期,数据库长期累积无用条目。

**修复思路**: `deleteItem` / `deleteItemWithoutUndo` 末尾检查所属 `DaySection` 的 items 是否为空,若空则一并删除(注意 undo 协作)。

---

### #9 `createItem` 触发双倍 refreshTrigger 与 scheduleSave

**位置**: `Models/TodoStore.swift:381-443`

**问题**: 调用 `getOrCreateSection`(line 363) bump trigger + schedule save 一次,然后自己 bump(line 436) + schedule save 再一次。每次新建条目浪费一次全列表重算和一次 task 取消/重建。

**修复思路**: `getOrCreateSection` 拆出 "纯创建" 和 "trigger+schedule" 两步,由调用方决定是否触发。

---

### #10 死代码 `Notification.Name("focusRequest")`

**位置**: `Models/UndoManager.swift:12-14`

**问题**: 声明了 Notification 名但全文无 post / addObserver,已被 `focusRequestId` 取代。

**修复**: 直接删除。

---

### #11 三处 `#Preview` 都执行 `TodoStore.shared.initialize(with:)`

**位置**: `TodoItemView.swift:296`、`DaySectionView.swift:481`、`TodoListView.swift:158`

**问题**: 多个 Preview 同时打开会互相 reset 单例,Preview Canvas 容易崩。不影响 Release,只影响开发体验。

**修复思路**: 给 Preview 用一个隔离的 `TodoStore` 实例(注入或测试专用初始化),不要共享 `.shared`。

---

## 验证记录

| 时间 | 场景 | 结果 |
|---|---|---|
| 2026-05-21 14:30 | Release 版重建后 sample (PID 45308) | CPU 0.0%,Physical footprint 93.2 MB,主线程 100% mach_msg 空闲 |
| 2026-05-21 14:38 | /Applications/ 替换后启动 (PID 54485) | CPU 0.3%,sleeping,正常 |

旧版 /Applications/todo block.app 已备份为 `/Applications/todo block.app.bak`(May 15 build),可在出现回归时回滚。
