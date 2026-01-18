# Todo Block 应用打包与分发指南

本文档详细说明如何将 Todo Block 项目打包为 `.app` 文件，以便分发给其他 Mac 用户使用。

## 前提条件

- 安装了 Xcode 的 Mac 电脑。
- 项目能够成功编译（已验证）。

## 方法一：使用 Xcode 图形界面（推荐）

这是最直观的方法，适合大多数场景。

1. **准备构建**
   - 打开 `todo block.xcodeproj`。
   - 在 Xcode 顶部工具栏，将目标设备（Destination）选为 **Any Mac (Apple Silicon, Intel)**。这一步确保应用能同时运行在 M1/M2/M3 和 Intel 芯片的 Mac 上。
   - 确保 Scheme 选中的是 `todo block`。

2. **执行归档 (Archive)**
   - 在菜单栏点击 **Product** -> **Archive**。
   - Xcode 将开始编译并打包应用。这可能需要几分钟。
   - 完成后，**Organizer** 窗口会自动弹出，并显示刚刚生成的 Archive 记录。

3. **导出应用 (Export)**
   - 在 Organizer 窗口中，选中最新的归档记录，点击右侧的 **Distribute App** 按钮。
   - 选择 **Custom**（或 Copy App），点击 Next。
   - 选择 **Copy App**（如果只是简单分享，不需要上传到 App Store），点击 Next。
   - 此时 Xcode 可能会询问签名方式：
     - 如果你有 Apple Developer 账号（付费），选择你的 Team 自动签名。
     - 如果**没有**付费账号，选择 **Development** 签名，或者如果只是自己小范围从源码编译，可以直接找到 Products 目录下的 app。
   - 导出后，你会得到一个包含 `.app` 的文件夹。

## 方法二：关于“未知开发者”提示 (Gatekeeper)

如果你没有使用付费的 Apple Developer账号对应用进行**公证 (Notarization)**，其他用户在打开应用时，macOS 会弹出警告：
> "Todo Block" 已损坏，无法打开。
> 或者
> "Todo Block" 出来自不明身份开发者...

### 解决方案

请指导接收应用的用户执行以下操作之一：

#### 方案 A：右键打开（一次性）
1. 不要直接双击图标。
2. **右键点击**应用图标，选择 **打开**。
3. 在弹出的警告框中点击 **打开** 按钮。
4. 之后就可以正常双击打开了。

#### 方案 B：移除隔离属性（彻底解决）
如果方案 A 无效，或者应用立刻闪退，可以让用户在终端执行以下命令：

```bash
xattr -cr /path/to/todo\ block.app
```
*(将 `/path/to/todo\ block.app` 替换为实际的应用路径，可以直接把 app 拖入终端)*

这条命令会移除 macOS 对该应用的安全隔离标记 (Quarantine Flag)。

## 高级：命令行构建 (可选)

如果你希望通过命令行快速生成 app（仅限此时此地运行，未签名）：

```bash
xcodebuild -project "todo block.xcodeproj" -scheme "todo block" -configuration Release -destination 'platform=macOS' build
```
构建产物通常位于 `DerivedData` 目录中，可以通过 Xcode -> Settings -> Locations 查看具体位置。
