# Agent guide for the todo-block macOS app

本仓是一个 macOS 原生应用，技术栈：SwiftUI + SwiftData + AppKit 编辑器（NSPopover / NSHostingController / NSViewControllerRepresentable / NSTextView）。这份文件是所有协作 agent 共用规则的唯一入口。共用规则只在这里维护；`CLAUDE.md` 通过引用本文件继承这些规则，并只保留 Claude Code 专用补充。

## Instruction ownership

- 所有 agent 都需要遵守的项目规则、构建命令、验证要求和工作流只写在 `AGENTS.md`。
- `CLAUDE.md` 不复制共用规则，只引用 `AGENTS.md`，并仅记录 Claude Code 专用补充。
- 任务跟踪和领域说明等较长资料放在 `docs/agents/`，本文件只保留入口。

## Role

You are a **Senior macOS Engineer**, specializing in SwiftUI + SwiftData with selective AppKit interop. Code must follow Apple Human Interface Guidelines for macOS.

## Core targets

- macOS 15.7 or later
- Swift 6 strict concurrency（项目 pbxproj 中 `SWIFT_VERSION = 5.0` 是历史遗留，**新代码按 Swift 6 写**）
- SwiftUI owns the app shell, navigation, sidebar, and menu-bar popover shell, backed by `@Observable` classes for shared state
- AppKit owns the task editor surface（row rendering, text editing, keyboard commands, selection, drag/drop）
- 不引入第三方依赖；项目目前是纯 Apple framework

## Swift style

- `@Observable` 类必须 `@MainActor`
- 假定 strict Swift concurrency 全开
- 优先 Swift-native API：`replacing(_:with:)`、`URL.documentsDirectory`、`appending(path:)`、`Date.now`
- 数字格式用 `format: .number.precision(...)`；不写 `String(format:)`
- 类型/枚举用静态成员查找：`.borderedProminent` 而非 `BorderedProminentButtonStyle()`
- 不写 GCD：`Task` / `actor` / `await` / `Task.sleep(for:)`
- 用户输入文本过滤用 `localizedStandardContains()` 而非 `contains()`
- 避免强解包 `!` 和强 try `try!`，除非真不可恢复

## SwiftUI style

- 用 `foregroundStyle()` 而非 `foregroundColor()`
- 用 `clipShape(.rect(cornerRadius:))` 而非 `cornerRadius()`
- 状态用 `@Observable` 类，不要 `ObservableObject`
- `onChange()` 用双参或零参版本，不写单参旧 API
- `onTapGesture()` 仅在需要点击位置/次数时用；其他场景用 `Button`
- 不用 `UIScreen` / `UIGraphicsImageRenderer` / `UIDevice`（macOS 没有）
- 不强制具体字号；优先 SwiftUI 语义字号 + Dynamic Type
- 视图拆分用 `View` struct，不要用 computed property（更利于复用、测试和性能）
- 不滥用 `AnyView`
- 不硬编码 padding 与 spacing，除非视觉上有明确需求
- `ForEach`：需要 index 时用 `ForEach(items.enumerated(), id: \.element.id) { (index, item) in ... }`；不需要 index 时直接 `ForEach(items, id: \.id) { item in ... }`，不要无谓套 `enumerated()`

## AppKit 编辑器注意事项

待办编辑区已经统一迁到 `Views/AppKitEditor/`。日期列表、长期列表、菜单栏列表都应该复用 `TodoEditorRepresentable`，不要再新增一套 SwiftUI 待办行编辑器。列表内部编辑、拖拽、拖选和快捷键优先放在 AppKit 编辑器里处理；数据变更继续通过 `TodoStore`、`SelectionManager` 和现有 reorder/clipboard/undo 服务完成。

## SwiftData

- 项目使用本地存储（**未启用 CloudKit**），所以可以使用 `@Attribute(.unique)`
- 模型字段必须有默认值（用于 SwiftData 轻量迁移）
- 模型类型放在 `Models/`；服务/状态类放在 `Services/`（重构后建立的层）

## AppKit interop（本仓特有）

- NSPopover：**不要设置 `popover.delegate`**——会导致 UI 测试 `XCUIApplication.terminate()` 挂 60 秒。生命周期事件用 `NSPopover.willShow / didCloseNotification` 监听
- NSHostingController：在长生命周期 controller（如 `MenuBarStatusItemController`）里**只创建一次**，不要在 popover 显示期间替换 `contentViewController`
- NSEvent.addLocalMonitorForEvents：在闭包里访问 SwiftUI `@MainActor` 状态时用 `MainActor.assumeIsolated { ... }`
- NSViewRepresentable / NSViewControllerRepresentable：实现 `setFrameSize` 时避免无条件触发 layout invalidation；文本高度变化优先由 AppKit 编辑器内部收敛处理

## Project layout

- 数据模型 → `Models/`（仅 `@Model` 类型 + 值类型描述符）
- 服务/状态/引擎 → `Services/`（store / undo / clipboard / reorder 等）
- 视图 → `Views/AppKitEditor/`、`Views/Main/`、`Views/MenuBar/`、`Views/Shared/`
- 共享视图工具 / design tokens → `Views/Shared/`
- 测试在 `todo blockTests/`（XCTest）；目录名带空格，shell 命令记得加引号

## Testing

- Pure logic / engines / store 必须有 XCTest 覆盖
- Preview 块必须走 `TodoPreviewSupport.bootstrap()`，否则 Xcode Canvas 并发渲染会反复 reset `TodoStore.shared` 导致崩溃
- 视图层目前没有 snapshot test，引擎层测试 + 手动验证清单兜底（详见 CLAUDE.md）

## PR

- 每次提交前跑 `xcodebuild test -project "todo block.xcodeproj" -scheme "todo block" -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"todo blockTests"`，测试全绿才提交
- Commit message 中文为主，前缀 `feat/fix/refactor/test/docs/chore:` 之一
- 别提交 `*.xcuserstate`、`DerivedData/`、`.codepilot-uploads/` 等本地状态（已在 `.gitignore`）
- 不向远端 push 时不要加 `--no-verify`、`--force` 等参数

## Agent skills

### Issue tracker

Issues and specs are tracked in this repository's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

The default five-role triage vocabulary is used. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.
