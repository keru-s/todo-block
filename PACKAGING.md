# 打包与分发

发布流程已统一到 GitHub Actions，手动打包仅用于本地验证。

## 正式发布（CI）

```bash
git tag vX.Y.Z && git push origin main vX.Y.Z
```

触发 `.github/workflows/objective-c-xcode.yml`：按 arm64 / x86_64 分别构建 Release，ad-hoc 签名后各产出一个 DMG（`Todo-Block-macOS-AppleSilicon.dmg` / `Todo-Block-macOS-Intel.dmg`），并附带安装说明发布到 GitHub Release。

签名要点（改动 workflow 时注意）：entitlements 必须同时包含 App Sandbox 和 `com.apple.security.files.user-selected.read-write`，缺后者导入/导出面板会静默不弹。

## 本地手动构建（未签名，仅供自测）

见 `AGENTS.md`「构建、测试、运行」中的 Unsigned Release build 命令，产物在 `build/DerivedData/Build/Products/Release/`。

## Gatekeeper 放行

发布包是 ad-hoc 签名（未公证），首次打开会被 Gatekeeper 拦截；放行方法见 `README.md`「下载」一节。
