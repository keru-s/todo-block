#!/bin/bash
# 快速编译并运行最新代码：./run.sh
set -e
cd "$(dirname "$0")"

APP="todo block"

# 退出正在运行的旧实例，避免覆盖失败或跑到旧版本
osascript -e "tell application \"$APP\" to quit" 2>/dev/null || true

# 团队 ID 可用环境变量覆盖：TODO_DEV_TEAM=XXXXXXXXXX ./run.sh
TEAM_ID="${TODO_DEV_TEAM:-4727XHULQX}"

# 用团队签名构建（覆盖 NoSigning.Debug.xcconfig），
# 这样沙盒生效、读写与 Xcode 构建相同的 SwiftData 容器
xcodebuild \
  -project "$APP.xcodeproj" \
  -scheme "$APP" \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  PROVISIONING_PROFILE_SPECIFIER= \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  SYMROOT="$PWD/build" \
  build | grep -E "error|warning: .*\.swift|BUILD" || true

open "build/Debug/$APP.app"
