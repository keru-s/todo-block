#!/bin/bash
# 为 macOS UI 测试临时选择已启用的系统键盘布局。
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "用法：$0 xcodebuild test ..." >&2
  exit 64
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/todo-block-keyboard.XXXXXX")"
keyboard="$work_dir/keyboard"
original=""
layout=""
child_pid=""

cleanup() {
  local result=$?
  local current
  trap - EXIT
  if [[ -n "$original" && -n "$layout" && "$original" != "$layout" ]]; then
    # 测试期间手动选择了别的输入法时，保留这个选择。
    if ! current="$("$keyboard" current)"; then
      echo "无法确认测试后的输入法，可能需要手动切回。" >&2
      if [[ "$result" == 0 ]]; then result=1; fi
    elif [[ "$current" == "$layout" ]]; then
      if ! "$keyboard" select "$original" || [[ "$("$keyboard" current)" != "$original" ]]; then
        echo "未能恢复测试前的输入法。" >&2
        if [[ "$result" == 0 ]]; then result=1; fi
      fi
    fi
  fi
  rm -rf -- "$work_dir"
  exit "$result"
}

stop_test() {
  local status="$1"
  if [[ -n "$child_pid" ]]; then
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'stop_test 129' HUP
trap 'stop_test 130' INT
trap 'stop_test 143' TERM

cat > "$work_dir/keyboard.swift" <<'SWIFT'
import Carbon
import Foundation

func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
}

func identifier(_ source: TISInputSource) -> String? {
    property(source, kTISPropertyInputSourceID) as? String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "current":
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let id = identifier(current) else {
        fail("无法读取当前输入法。")
    }
    print(id)
case "layout", "select":
    let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
    var enabledSources: [TISInputSource] = []
    for case let source as TISInputSource in sources {
        enabledSources.append(source)
    }
    if arguments == ["layout"] {
        let layouts = enabledSources.compactMap { source -> String? in
            guard property(source, kTISPropertyInputSourceType) as? String == kTISTypeKeyboardLayout as String,
                  property(source, kTISPropertyInputSourceIsASCIICapable) as? Bool == true,
                  let id = identifier(source),
                  id.hasPrefix("com.apple.keylayout.") else { return nil }
            return id
        }
        guard let id = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].first(where: layouts.contains)
            ?? layouts.first else {
            fail("请先在系统的输入法设置中添加 ABC 或其他系统键盘布局。")
        }
        print(id)
    } else if arguments.count == 2,
              let source = enabledSources.first(where: { identifier($0) == arguments[1] }) {
        let status = TISSelectInputSource(source)
        guard status == noErr else { fail("切换输入法失败（\(status)）。") }
    } else {
        fail("找不到要选中的已启用输入法。")
    }
default:
    fail("未知的输入法操作。")
}
SWIFT

xcrun swiftc "$work_dir/keyboard.swift" -o "$keyboard"
original="$("$keyboard" current)"
layout="$("$keyboard" layout)"
if [[ "$original" != "$layout" ]]; then
  "$keyboard" select "$layout"
  if [[ "$("$keyboard" current)" != "$layout" ]]; then
    echo "系统键盘布局未生效，已停止启动 UI 测试。" >&2
    exit 1
  fi
fi

"$@" <&0 &
child_pid=$!
wait "$child_pid"
