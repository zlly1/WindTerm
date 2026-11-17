#!/bin/bash
#
# install.sh — 安装 LaunchAgent，让补丁在 WindTerm 升级/重装后自动重新生效
#
# 触发时机：
#   1) 登录时（RunAtLoad）
#   2) 配置目录被改动时（WatchPaths，升级/重装会触发）
#
# 卸载：./uninstall.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_SCRIPT="$SCRIPT_DIR/fix-windterm-kbdint.sh"
LABEL="com.zlly1.windterm-kbdint"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="${1:-/Applications/WindTerm.app}"

[ -f "$FIX_SCRIPT" ] || { echo "ERROR: 缺少 $FIX_SCRIPT" >&2; exit 1; }
[ -d "$APP" ] || { echo "ERROR: 未找到 $APP" >&2; exit 1; }

chmod +x "$FIX_SCRIPT"

echo "==> 先执行一次补丁"
"$FIX_SCRIPT" "$APP"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$FIX_SCRIPT</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>WatchPaths</key>
    <array>
        <string>$APP/Contents/MacOS/terminal/configs</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/$LABEL.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$LABEL.log</string>
</dict>
</plist>
PLIST_EOF

plutil -lint "$PLIST" >/dev/null || { echo "ERROR: plist 校验失败" >&2; exit 1; }
chmod 644 "$PLIST"

# 新版 macOS 用 bootstrap/bootout；旧版回退到 load/unload
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM" "$PLIST" 2>/dev/null || true

LOADED=0
if launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null; then
    LOADED=1
elif launchctl load "$PLIST" 2>/dev/null; then
    LOADED=1
fi

echo ""
echo "==> plist 已写入: $PLIST"
if [ "$LOADED" -eq 1 ]; then
    echo "    状态: 已加载"
    echo "    校验: launchctl list | grep windterm-kbdint"
else
    echo "    状态: 写入成功，但当前环境无法加载到 launchd"
    echo "          （在非 GUI 会话/受限进程里 bootstrap 会返回 EIO，属正常现象）"
    echo ""
    echo "    请在【终端.app】里手动执行一次："
    echo "      launchctl bootstrap gui/$UID_NUM \"$PLIST\""
    echo "    然后校验："
    echo "      launchctl list | grep windterm-kbdint"
fi
echo "    日志: /tmp/$LABEL.log"
echo ""
echo "完成。之后 WindTerm 升级/重装会自动重新应用补丁。"
