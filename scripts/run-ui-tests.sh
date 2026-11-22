#!/bin/bash
# 运行带开发签名的 macOS UI 测试。
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
用法：./scripts/run-ui-tests.sh [--keep-input-source] [测试类[/测试方法] ...]
不指定用例时运行 UI 测试 target。可用 TODO_DEV_TEAM 指定开发团队。
USAGE
  exit 0
fi

keep_input_source=false
if [[ "${1:-}" == "--keep-input-source" ]]; then
  keep_input_source=true
  shift
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
target="todo blockUITests"
selectors=()
for selection in "$@"; do
  selectors+=("-only-testing:$target/$selection")
done
if [[ $# -eq 0 ]]; then
  selectors=("-only-testing:$target")
fi

test_command=(
  xcodebuild test
  -project "todo block.xcodeproj" -scheme "todo block"
  -configuration Debug -destination 'platform=macOS'
  -derivedDataPath build/SignedDerivedData -parallel-testing-enabled NO
  "${selectors[@]}"
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic
  "CODE_SIGN_IDENTITY=Apple Development" PROVISIONING_PROFILE_SPECIFIER=
  "DEVELOPMENT_TEAM=${TODO_DEV_TEAM:-4727XHULQX}"
)

if "$keep_input_source"; then
  exec "${test_command[@]}"
fi
exec "$repo_dir/scripts/with-system-keyboard.sh" "${test_command[@]}"
