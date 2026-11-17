#!/bin/bash
#
# fix-windterm-kbdint.sh
#
# 永久规避 WindTerm 2.7.0 在 keyboard-interactive 认证时的空指针崩溃。
#
# 现象：连接提供 keyboard-interactive 认证的 SSH 服务器时，WindTerm 在
#       输入密码前后直接崩溃（SIGSEGV，KERN_INVALID_ADDRESS at 0x8），
#       故障栈顶为 Ssh::Session::authInteractive(QByteArray const&)。
#       该函数位于 WindTerm 闭源部分，无法从源码侧修复。
#
# 原理：把 session 配置中的 ssh.authKeyboardInteractive 置为 false，
#       让客户端只走 password / publickey 认证，绕开崩溃路径。
#
# 特性：幂等；可重复执行；WindTerm 升级/重装后重跑即可恢复；
#       修改后用 plutil 校验 JSON，校验失败自动回滚。
#
# 用法：
#   ./fix-windterm-kbdint.sh                # 处理默认路径 /Applications/WindTerm.app
#   ./fix-windterm-kbdint.sh /path/to/WindTerm.app
#
set -uo pipefail

APP="${1:-/Applications/WindTerm.app}"
KEY="ssh.authKeyboardInteractive"
CHANGED=0

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || fail "未找到 WindTerm.app: $APP"

CONFIG_DIR="$APP/Contents/MacOS/terminal/configs"
[ -d "$CONFIG_DIR" ] || fail "未找到配置目录: $CONFIG_DIR"

# 收集所有可能带该键的配置文件：默认模板 + 已保存的会话（去重）
FILES=()
while IFS= read -r f; do
    [ -n "$f" ] && FILES+=("$f")
done < <(find "$APP/Contents/MacOS" -type f \( -name '*.session' -o -name 'session.config' \) 2>/dev/null | sort -u)

if [ ${#FILES[@]} -eq 0 ]; then
    fail "未找到任何 session 配置文件"
fi

for f in "${FILES[@]}"; do
    # 只处理确实包含该键的文件
    grep -q "\"$KEY\"" "$f" 2>/dev/null || continue

    # 已经是 false 就跳过（幂等）
    if grep -qE "\"$KEY\"[[:space:]]*:[[:space:]]*false" "$f"; then
        log "  [skip] $(basename "$f") 已是 false"
        continue
    fi

    BACKUP="${f}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$f" "$BACKUP" || fail "备份失败: $f"

    /usr/bin/sed -i '' \
        "s/\"$KEY\"[[:space:]]*:[[:space:]]*true/\"$KEY\": false/g" "$f"

    # 校验 JSON（-lint 依赖扩展名，这里用 -convert 强制解析），坏了就回滚
    if ! /usr/bin/plutil -convert xml1 -o /dev/null "$f" >/dev/null 2>&1; then
        mv -f "$BACKUP" "$f"
        fail "JSON 校验失败，已回滚: $f"
    fi

    rm -f "$BACKUP"
    log "  [fixed] $f  ($KEY -> false)"
    CHANGED=$((CHANGED + 1))
done

if [ "$CHANGED" -eq 0 ]; then
    log "无需修改，所有配置已是安全状态。"
else
    log ""
    log "已修复 $CHANGED 个配置文件。"
    log "注意：需要重启 WindTerm 才会生效。"
fi

exit 0
