#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/build/Peanut Service Manager.app"
DESTINATION="/Applications/Peanut Service Manager.app"
STAGING="/Applications/.Peanut Service Manager.app.new"
BACKUP="/Applications/.Peanut Service Manager.app.backup"
LABEL="org.peanutopensource.PeanutServiceManager.supervisor"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
EXECUTABLE="$DESTINATION/Contents/MacOS/peanut-service-manager"
HELPER="$DESTINATION/Contents/Library/LaunchServices/peanut-service-supervisor"

if pgrep -f "$EXECUTABLE" >/dev/null 2>&1; then
  echo "请先正常退出已安装的花生服务管理器，再运行安装脚本。" >&2
  exit 1
fi
if [[ -e "$STAGING" || -e "$BACKUP" ]]; then
  echo "发现安装暂存目录或备份目录，未覆盖：$STAGING / $BACKUP" >&2
  exit 1
fi
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "共享 supervisor 仍已加载，未构建或替换应用。请在所有服务和客户端安全退出后安排更新窗口。" >&2
  echo "目标：$HELPER" >&2
  exit 1
fi
if [[ -f "$AGENT" ]]; then
  EXISTING_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$AGENT")"
  EXISTING_HELPER="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$AGENT")"
  if [[ "$EXISTING_LABEL" != "$LABEL" || "$EXISTING_HELPER" != "$HELPER" ]]; then
    echo "现有 supervisor LaunchAgent 指向其他安装位置。为避免中断服务，未替换应用或配置。" >&2
    echo "当前路径：$EXISTING_HELPER" >&2
    exit 1
  fi
fi
"$ROOT/scripts/package-app.sh" release
SOURCE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
if [[ "$SOURCE_ID" != "org.peanutopensource.PeanutServiceManager" ]]; then
  echo "构建产物的应用标识不匹配，停止安装。" >&2
  exit 1
fi

ditto "$SOURCE_APP" "$STAGING"
MOVED_OLD=0
cleanup() {
  if [[ "$MOVED_OLD" == 1 && ! -e "$DESTINATION" && -e "$BACKUP" ]]; then
    mv "$BACKUP" "$DESTINATION"
  fi
  [[ ! -e "$STAGING" ]] || rm -rf "$STAGING"
}
trap cleanup EXIT
if [[ -e "$DESTINATION" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$EXISTING_ID" != "org.peanutopensource.PeanutServiceManager" ]]; then
    echo "目标位置已有其他应用，未覆盖：$DESTINATION" >&2
    exit 1
  fi
  mv "$DESTINATION" "$BACKUP"
  MOVED_OLD=1
fi
mv "$STAGING" "$DESTINATION"
if [[ "$MOVED_OLD" == 1 ]]; then rm -rf "$BACKUP"; MOVED_OLD=0; fi
trap - EXIT

echo "已安装：$DESTINATION"
echo "版本：$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")"
echo "应用包大小：$(du -sh "$DESTINATION" | awk '{print $1}')"
open -n "$DESTINATION"
