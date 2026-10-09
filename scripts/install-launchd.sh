#!/bin/bash
# 安装 / 卸载 Surge 配置自动同步的 launchd 任务。
#   ./scripts/install-launchd.sh            安装（iCloud 目录有变化时触发，另外每小时兜底跑一次）
#   ./scripts/install-launchd.sh uninstall  卸载

set -euo pipefail

LABEL="com.github.surge-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/surge-sync.sh"
SRC="${SURGE_SRC:-$HOME/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents}"
LOG="$HOME/Library/Logs/surge-sync.log"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "uninstall" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "已卸载 $LABEL"
  exit 0
fi

[ -d "$SRC" ] || { echo "找不到 Surge 配置目录：$SRC（可用 SURGE_SRC=... 指定）"; exit 1; }
chmod +x "$SCRIPT"
mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
E_SCRIPT="$(printf '%s' "$SCRIPT" | xml_escape)"
E_SRC="$(printf '%s' "$SRC" | xml_escape)"
E_LOG="$(printf '%s' "$LOG" | xml_escape)"
E_REPO="$(printf '%s' "$REPO_DIR" | xml_escape)"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$E_SCRIPT</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>SURGE_SRC</key><string>$E_SRC</string>
  </dict>
  <key>WorkingDirectory</key><string>$E_REPO</string>
  <key>WatchPaths</key>
  <array>
    <string>$E_SRC</string>
  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>ThrottleInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$E_LOG</string>
  <key>StandardErrorPath</key><string>$E_LOG</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"

echo "已安装 $LABEL"
echo "  监听目录：$SRC"
echo "  日志：    $LOG"
echo "  立即运行：launchctl kickstart -k $DOMAIN/$LABEL"
