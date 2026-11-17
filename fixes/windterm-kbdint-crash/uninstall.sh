#!/bin/bash
#
# uninstall.sh — 卸载 LaunchAgent 并恢复 WindTerm 默认认证配置
#
set -uo pipefail

LABEL="com.zlly1.windterm-kbdint"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="${1:-/Applications/WindTerm.app}"
KEY="ssh.authKeyboardInteractive"

if [ -f "$PLIST" ]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "已移除 LaunchAgent: $PLIST"
else
    echo "未找到 LaunchAgent，跳过。"
fi

# 恢复默认值（true）
CONFIG="$APP/Contents/MacOS/terminal/configs/session.config"
if [ -f "$CONFIG" ] && grep -q "\"$KEY\"" "$CONFIG"; then
    /usr/bin/sed -i '' \
        "s/\"$KEY\"[[:space:]]*:[[:space:]]*false/\"$KEY\": true/g" "$CONFIG"
    if /usr/bin/plutil -lint "$CONFIG" >/dev/null 2>&1; then
        echo "已恢复 $KEY = true（注意：崩溃问题会重新出现）"
    else
        echo "WARNING: 恢复后 JSON 校验失败，请检查 $CONFIG" >&2
    fi
fi

echo "卸载完成。"
