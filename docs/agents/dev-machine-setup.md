# 开发机免密自动化测试配置

目标：新机器上无人值守跑 `xcodebuild test`（单元 + UI）和 `./run.sh`（团队签名构建），全程不弹密码/授权框。

macOS 有多套**互不相关**的授权机制，按弹框文字区分是唯一可靠的诊断方法——开错一道闸没用。每项配置下标注了证据等级：

- **本机验证**：做过前后对照实验（改之前复现症状，改之后无人值守跑通）
- **机制确认**：Apple 文档/工具行为层面确定必需，但本机未做反向验证
- **预防配置**：按机制配置，未观察到它修复过实际症状

## 诊断：看弹框认机制

UI 测试无弹框却全体失败（app 无窗口、launch 超时）时，先查 console 会话是否锁屏：`ioreg -n IODisplayWrangler | grep -i IOConsoleLocked`。锁屏状态下系统不为任何 app 建窗（TextEdit 也开不出窗口），UI 测试必挂；解锁后重跑即可，不要误判为代码回归。

| 弹框内容 | 机制 | 影响的场景 |
| --- | --- | --- |
| 调试器/开发者工具授权（要密码） | Developer Mode | 单元测试 |
| 「XCTest is trying to Enable UI Automation. Enter the password…」（要密码） | Authorization Services | UI 测试 |
| 「XX 想要控制这台电脑」（允许/不允许，不要密码） | TCC 辅助功能 | UI 测试 |
| 「codesign 想要使用钥匙串中的密钥」（要密码） | 钥匙串私钥分区列表 | 仅 `./run.sh` 签名构建 |

## 场景 A：单元测试

只需 **Developer Mode**（本机验证：开启前每次弹密码，开启后后台无人值守跑完全部测试）：

```bash
sudo DevToolsSecurity -enable
```

前提：账号在 `_developer` 组（装过 Xcode 默认即在）。验证：

```bash
DevToolsSecurity -status   # 期望: enabled
id -Gn "$(whoami)" | grep -o _developer
```

本仓 Debug 构建不签名（`Config/NoSigning.Debug.xcconfig` 设 `CODE_SIGNING_ALLOWED = NO`），**跑测试不碰钥匙串**，无需任何签名相关配置。

## 场景 B：UI 测试

需要两道，缺一不可：

**B1. Automation Mode**（本机验证：配置前 `requires user authentication` 且实际弹密码框；配置后 `DOES NOT REQUIRE`，UI 测试全程无弹框）：

```bash
sudo /usr/bin/automationmodetool enable-automationmode-without-authentication
/usr/bin/automationmodetool   # 验证: DOES NOT REQUIRE user authentication
```

此授权不写 TCC 数据库，弹框批准也不会持久化——所以「看到弹框点了同意但下次还弹」是它的典型症状，必须用命令解决。

**B2. TCC 辅助功能 + PostEvent**（机制确认：XCUITest runner 无此授权无法驱动被测 app；本机未做撤销后的反向验证）：

授权对象是每个 UI 测试 target 的 runner，本项目为 `insight.notion-to-doUITests.xctrunner`。首次跑 UI 测试时在「允许/不允许」框点「允许」即持久记录。验证：

```bash
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT service, client, auth_value FROM access WHERE client LIKE '%xctrunner%';"
# 期望: kTCCServiceAccessibility 和 kTCCServicePostEvent 均 auth_value=2
```

会触发重新授权的边界：改 UI 测试 target 的 bundle ID、`tccutil reset Accessibility`、runner 签名 requirement 失配（未签名/ad-hoc 构建的 requirement 跟踪具体二进制，重编译即失效）。

## 场景 C：`./run.sh` 团队签名构建

只需**钥匙串私钥分区列表**（预防配置：配置时未观察到实际 codesign 弹框，与跑测试无关）：

```bash
security set-key-partition-list -S apple-tool:,apple: -s -k "登录密码" ~/Library/Keychains/login.keychain-db
```

不配也可以：首次签名弹框时点「**始终允许**」效果等同，且是严格按需的。验证（无弹框完成签名即通过）：

```bash
security find-identity -v -p codesigning        # 取一个证书 SHA-1
echo test > /tmp/t && codesign -s <SHA-1> --force /tmp/t && rm /tmp/t
```

维护：钥匙串里搜 `Apple Development`，删掉已吊销（revoked）的证书，避免自动签名误选失效身份。

## 最终验证

```bash
xcodebuild test -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:"todo blockTests"        # 单元测试（场景 A）

xcodebuild test -project "todo block.xcodeproj" -scheme "todo block" \
  -destination 'platform=macOS' \
  -only-testing:"todo blockUITests"      # UI 测试（场景 B），会短暂接管键鼠
```

两次全程无弹框即配置完成。

## 反模式

- **不要创建 `/private/var/db/.AccessibilityAPIEnabled`**：macOS 10.x 时代的旧全局开关，与 Automation Mode 无关；若被旧代码读取等于全局放开辅助功能 API，是安全隐患。
- **不要把「做过某操作且最终结果正常」当作该操作必要的证据**——逐项做前后对照，或在文档里标注证据等级。本文 2026-08 首次编写时曾把场景 C 的配置误记为跑测试必需。
