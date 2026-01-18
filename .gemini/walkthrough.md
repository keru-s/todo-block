# Notion 风格 To-Do Mac 应用 - Walkthrough

## 完成概览

成功实现了一个 Mac 本地 To-Do 应用的核心功能，采用 Swift + SwiftData 技术栈。

---

## 项目结构

```
notion to do/
├── Models/
│   ├── TodoItem.swift      # 待办事项模型
│   ├── DaySection.swift    # 日期分组模型
│   └── TodoDataService.swift # 数据服务层
├── Views/
│   ├── Main/
│   │   ├── SidebarView.swift   # 月份侧边栏
│   │   └── TodoListView.swift  # 待办列表主视图
│   ├── Editor/
│   │   ├── DaySectionView.swift # 日期分组视图
│   │   └── TodoItemView.swift   # 单个待办项视图（核心组件，同时用于 Main 和 MenuBar）
│   └── MenuBar/
│       └── MenuBarView.swift    # 菜单栏弹出窗口（复用了 TodoItemView）
├── ContentView.swift       # 主入口视图
└── notion_to_doApp.swift   # App 入口
```

---

## 核心功能

### ✅ 已实现

| 功能 | 描述 |
|------|------|
| **数据持久化** | SwiftData 存储，支持异步防抖保存 |
| **日期分组** | 待办按日期分组显示，标题可编辑 |
| **层级嵌套** | 最多 4 层子任务，Tab/Shift+Tab 调整 |
| **键盘操作** | Enter 创建、Backspace 删除、方向键导航 |
| **父子同步** | 父任务完成时子任务同步完成 |
| **菜单栏** | 完整功能的迷你窗口，支持编辑、多选、快捷键 |
| **多选操作** | Shift+Click 范围选择，Delete 批量删除 |
| **跨窗口同步** | 菜单栏修改实时同步至主窗口（Item Title 监听机制） |
| **拖拽句柄** | 鼠标悬停显示拖拽手柄 |

### 🔜 待完善

- 拖拽排序（同日期内 + 跨日期）
- 拖拽时层级指示器
- 菜单栏内拖拽

---

## 键盘快捷键

| 按键 | 功能 |
|------|------|
| `Enter` | 在当前项下方创建新待办 |
| `Backspace` | 删除空待办（内容为空时） |
| `Tab` | 增加缩进层级 |
| `Shift+Tab` | 减少缩进层级 |
| `↑` / `↓` | 在待办间上下移动 |
| `Space` | 切换完成状态（需选中复选框） |
| `Shift+Click` | 多选范围内的待办事项 |

---

## 架构演进记录

### 1. 数据驱动 (Data Driven)
- 从直接查询 SwiftData 改为单例 `TodoStore` + 内存缓存。
- 解决了快速操作下的 Index Out of Bounds 问题。
- 实现了主窗口与菜单栏的数据共享。

### 2. 组件复用 (Component Reuse)
- **挑战**：菜单栏原本使用简化的视图，导致样式不一致且缺少中划线支持。
- **方案**：重构 `MenuBarView`，完全复用主界面的 `TodoItemView` 组件。
- **收益**：
  - 菜单栏获得了完整的编辑能力（快捷键、缩进、多选）。
  - 解决了 `TextField` 样式问题（统一使用 `CustomTextField`）。
  - 极大地减少了代码重复。

### 3. 实时同步 (Real-time Sync)
- **问题**：菜单栏修改后，主窗口的 `TextField` (`@State`) 不会立即更新。
- **修复**：在 `TodoItemView` 中添加 `onChange(of: item.title)` 监听器，确保数据模型的外部变更能立即反映在 UI 上。

---

## 运行应用

```bash
# 在 Xcode 中打开项目
open "notion to do.xcodeproj"

# 或通过命令行构建运行
xcodebuild -project "notion to do.xcodeproj" -scheme "notion to do" -destination 'platform=macOS' build
```

构建成功后，应用将显示:
- 左侧: 月份侧边栏
- 右侧: 按日期分组的待办列表
- 菜单栏: 待办图标（点击显示今日待办）
