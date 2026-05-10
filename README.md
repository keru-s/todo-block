# Todo Block

[中文](README.md) | [English](README.en.md)

Todo Block 是一个原生 macOS 待办应用，支持分层任务、键盘优先操作、菜单栏快速查看，以及按日期整理任务。

## 截图

![Todo Block 启动画面](docs/images/todo-block-startup.png)

## 功能特点

- 原生 macOS 体验：基于 SwiftUI 和 SwiftData 构建
- 分层任务：支持最多 4 层子任务
- 键盘优先：创建、编辑、移动任务都可以直接用键盘完成
- 日期分组：任务按日期自动归类，分区标题可编辑
- 菜单栏入口：不切换窗口也能快速查看今天的待办
- 拖拽排序：支持列表内和列表间拖拽整理
- 多选操作：支持 `Shift + 点击` 范围选择
- 实时同步：菜单栏和主窗口内容保持同步
- 撤销重做：常见操作支持撤销和重做
- 长期任务：支持长期事项分桶管理

## 下载

- 最新版本页面：[GitHub Releases](https://github.com/keru-s/todo-block/releases/latest)
- 直接下载：[Todo-Block-macOS.zip](https://github.com/keru-s/todo-block/releases/latest/download/Todo-Block-macOS.zip)

如果 macOS 提示应用已损坏或应被移到废纸篓，可以在终端执行：

```bash
xattr -dr com.apple.quarantine "/Applications/todo block.app"
```

## 运行要求

- 系统：macOS 15.7 或更高版本
- 开发：Xcode 26.0 或更高版本

## 安装与运行

### 直接安装

1. 从 Releases 下载压缩包。
2. 解压后把 `todo block.app` 拖到“应用程序”文件夹。
3. 首次打开如果遇到系统拦截，先执行上面的终端命令，再重新打开。

### 从源码运行

```bash
git clone https://github.com/keru-s/todo-block.git
cd todo-block
open "todo block.xcodeproj"
```

打开后在 Xcode 中直接运行即可。

### 命令行构建

```bash
xcodebuild -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS' \
  build
```

## 快捷键

| 快捷键 | 作用 |
|--------|------|
| `Enter` | 在当前任务下方新建任务 |
| `Backspace` | 删除空任务 |
| `Tab` | 增加缩进 |
| `Shift+Tab` | 减少缩进 |
| `↑` / `↓` | 在任务间移动 |
| `⌘↑` / `⌘↓` | 上移或下移任务 |
| `Space` | 切换完成状态 |
| `Shift+Click` | 范围多选 |
| `⌘Z` | 撤销 |
| `⌘⇧Z` | 重做 |
| `⌘C` | 复制任务 |
| `⌘V` | 粘贴任务 |

## 项目结构

```text
todo block/
├── Models/         # 数据模型、存储、撤销、剪贴板等核心逻辑
├── Views/
│   ├── Main/       # 主窗口
│   ├── Editor/     # 任务编辑相关视图
│   ├── MenuBar/    # 菜单栏界面
│   └── Shared/     # 共享拖拽与排序逻辑
├── ContentView.swift
└── todo_blockApp.swift
```

## 开发

### 运行测试

```bash
xcodebuild test \
  -project "todo block.xcodeproj" \
  -scheme "todo block" \
  -destination 'platform=macOS'
```

### 发布打包

正式发布通过推送 `v` 开头的标签触发，例如：

```bash
git tag v0.1.0
git push origin main v0.1.0
```

触发后，GitHub Action 会自动构建 Release 版本、生成 `Todo-Block-macOS.zip`，并把它挂到 GitHub Release 页面。

如果只是想先试跑打包流程，也可以在 GitHub Actions 页面手动运行工作流。手动运行会生成下载产物，但不会创建正式 Release。

## 技术栈

- Swift 6.2
- SwiftUI
- SwiftData
- `@Observable`

## 许可证

MIT
