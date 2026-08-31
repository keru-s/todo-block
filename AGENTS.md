# Agent guide for the todo-block macOS app

本仓是一个 macOS 原生应用，技术栈：SwiftUI + SwiftData + AppKit 编辑器（NSPopover / NSHostingController / NSViewControllerRepresentable / NSTextView）。这份文件是所有协作 agent 共用规则的唯一入口，共用规则只在这里维护，不再保留第二份规则文件。

## Instruction ownership

- 所有 agent 都需要遵守的项目规则、构建命令、验证要求和工作流只写在 `AGENTS.md`。
- 任务跟踪和领域说明等较长资料放在 `docs/agents/`，本文件只保留入口。

## Role

You are a **Senior macOS Engineer**, specializing in SwiftUI + SwiftData with selective AppKit interop. Code must follow Apple Human Interface Guidelines for macOS.

## Core targets

- macOS 15.7 or later（Xcode 26 构建，Bundle ID `com.insight.to-do-block`）
- Swift 6 strict concurrency（项目 pbxproj 中 `SWIFT_VERSION = 5.0` 是历史遗留，**新代码按 Swift 6 写**）
- SwiftUI owns the app shell, navigation, sidebar, and menu-bar popover shell, backed by `@Observable` classes for shared state
- AppKit owns the task editor surface（row rendering, text editing, keyboard commands, selection, drag/drop）
- 不引入第三方依赖；项目目前是纯 Apple framework

## Swift style

- `@Observable` 类必须 `@MainActor`
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
- 不硬编码 padding 与 spacing，除非视觉上有明确需求
- `ForEach`：需要 index 时用 `ForEach(items.enumerated(), id: \.element.id) { (index, item) in ... }`；不需要 index 时直接 `ForEach(items, id: \.id) { item in ... }`，不要无谓套 `enumerated()`

## AppKit 编辑器注意事项

待办编辑区已经统一迁到 `Views/AppKitEditor/`。日期列表、长期列表、菜单栏列表都应该复用 `TodoEditorRepresentable`，不要再新增一套 SwiftUI 待办行编辑器。列表内部编辑、拖拽、拖选和快捷键优先放在 AppKit 编辑器里处理；数据变更继续通过 `TodoStore`、`SelectionManager` 和现有 reorder/clipboard/undo 服务完成。

- `TodoEditorViewController` owns the AppKit list surface, row reuse, drop indicator, and drag/selection routing.
- `TodoEditorRowView` owns row-level input: checkbox, drag handle, `NSTextView`, row focus, Space toggle, Command+Up/Down, and left-button long-press multi-select.
- `TodoListActionModule` is the boundary back into `TodoStore` and `SelectionManager`. Keep persistence, reorder, undo, clipboard, and selection rules in services rather than duplicating them in views.
- `TodoEditorTextView` preserves IME composition state. Do not handle destructive commands while `hasMarkedText()` is true.

## SwiftData

- 项目使用本地存储（**未启用 CloudKit**），所以可以使用 `@Attribute(.unique)`
- 模型字段必须有默认值（用于 SwiftData 轻量迁移）
- 三个 `@Model`：`TodoItem`（`id`、`title`、`isCompleted`、`indentLevel` 0–4、`sortOrder` Double、`containerKindRaw`、`dayDate` 起始日）、`DaySection`（按日期键的分组头，标题可编辑）、`TodoBackupConsumptionState`（仅持久记录恢复点消费状态的内部标记，不属于用户的待办或日期分组数据）
- 不使用 SwiftData relationships，靠 `dayDate`/`containerKind` 匹配归属；`TodoItem.containerKind` getter 带 `?? .scheduled` 兜底，防御旧数据空的 `containerKindRaw`

## AppKit interop（本仓特有）

- NSPopover：**不要设置 `popover.delegate`**——会导致 UI 测试 `XCUIApplication.terminate()` 挂 60 秒。生命周期事件用 `NSPopover.willShow / didCloseNotification` 监听；`MenuBarStatusItemController` 将其转发为 `.menuBarPopoverWillShow` / `.menuBarPopoverDidClose`（见 `MenuBarPopoverNotifications.swift`）
- NSHostingController：在长生命周期 controller（如 `MenuBarStatusItemController`）里**只创建一次**，不要在 popover 显示期间替换 `contentViewController`（显示中替换会直接关掉 popover）
- NSEvent.addLocalMonitorForEvents：在闭包里访问 SwiftUI `@MainActor` 状态时用 `MainActor.assumeIsolated { ... }`
- NSViewRepresentable / NSViewControllerRepresentable：实现 `setFrameSize` 时避免无条件触发 layout invalidation；文本高度变化优先由 AppKit 编辑器内部收敛处理

## Project layout

- 数据模型 → `Models/`（仅 `@Model` 类型 + 值类型描述符）
- 服务/状态/引擎 → `Services/`（store / undo / clipboard / reorder 等）
- 视图 → `Views/AppKitEditor/`、`Views/Main/`、`Views/MenuBar/`、`Views/Shared/`
- 共享视图工具 / design tokens → `Views/Shared/`
- 测试在 `todo blockTests/`（XCTest）；目录名带空格，shell 命令记得加引号

## 构建、测试、运行

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

- `./run.sh`：退出旧实例 → 团队签名编译 Debug → 打开 `build/Debug/todo block.app`，不用开 Xcode
- 必须用团队签名（脚本内已覆盖 `Config/NoSigning.Debug.xcconfig`），否则沙盒不生效，SwiftData 会写到沙盒容器外的孤立目录，和 Xcode 构建的数据不通
- 签名团队 ID 默认 `4727XHULQX`，可用 `TODO_DEV_TEAM` 环境变量覆盖
- `buildServer.json` 为 SourceKit-LSP 接入 `xcode-build-server`；在 Xcode 之外编辑时用 `brew install xcode-build-server` 安装
- **交互会话中每次代码改动后自动跑上面的 Debug 构建**，构建失败先修好再宣布完成；构建成功后杀掉运行中的实例并重启新构建的 `.app`（`pkill -f "todo block.app"` 后打开 `BUILT_PRODUCTS_DIR` 下的 app），让用户立即验证。仅文档/注释改动、用户说自己启动、或只跑了测试时跳过重启
- **Release 流程**：`git tag v0.1.0 && git push origin main v0.1.0` 触发 `.github/workflows/objective-c-xcode.yml`，构建未签名 Release 并把 `Todo-Block-macOS.dmg` 上传到 GitHub Release；手动打包见 `PACKAGING.md`

## Architecture

`TodoStore.shared` 是唯一运行期状态源；视图代码永远不要直接写它的内部缓存（friendship 边界）。改动 store / 撤销恢复 / 当前列表接管 / 拖拽 / 选择相关代码前 → `docs/agents/architecture.md`（缓存 friendship 详情、操作历史、接管规则、拖拽与选择约定）。

## Testing

- Pure logic / engines / store 必须有 XCTest 覆盖
- XCTest 与 Swift Testing 并存；store/engine 逻辑的新测试沿用现有 XCTest 风格保持一致
- 测试 target 名带空格（`"todo blockTests"`）；测试 bundle id 是历史遗留的 `insight.notion-to-doTests`，不要去"修"它
- 本地验证跑 `-only-testing:"todo blockTests"`；未签名本地构建下启动 UI 测试 runner 可能触发 macOS "app is damaged" 对话框
- Preview 块必须走 `TodoPreviewSupport.bootstrap()`（共享一个内存 `ModelContainer`），否则 Xcode Canvas 并发渲染会反复 reset `TodoStore.shared` 导致崩溃
- 视图层目前没有 snapshot test，引擎层测试 + 手动验证清单兜底
- 新机器配置、或跑测试/`./run.sh` 弹密码/授权框（调试器、Enable UI Automation、辅助功能、codesign 钥匙串）→ `docs/agents/dev-machine-setup.md`（按弹框文字诊断机制，附证据等级）

## 仓库约定

- 历史上修过的性能/正确性问题清单在 `docs/code-review-todos.md`——回归看起来眼熟时先查它

## PR

- 每次提交前跑上面「构建、测试、运行」中的单测命令（含 `-parallel-testing-enabled NO`），测试全绿才提交
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
