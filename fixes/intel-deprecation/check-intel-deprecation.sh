#!/bin/bash
#
# check-intel-deprecation.sh — 诊断 WindTerm 的「Intel 组件将不再支持」问题
#
# 说明：WindTerm 官方只提供 x86_64 的 macOS 包，应用层（Ssh::Session 等）
#       是闭源的，无法在本仓库内重新编译出 arm64 版本。
#       本脚本只做客观诊断，不改动任何东西。
#
set -uo pipefail

APP="${1:-/Applications/WindTerm.app}"
echo "=== WindTerm Intel 兼容性诊断 ==="
echo ""

if [ ! -d "$APP" ]; then
    echo "未找到 $APP"
    exit 1
fi

BIN="$APP/Contents/MacOS/WindTerm"
echo "[1] 主程序架构"
file -b "$BIN"
ARCHS=$(file -b "$BIN" | grep -oE "arm64|x86_64" | sort -u | tr '\n' ' ')
echo "    架构: $ARCHS"
case "$ARCHS" in
    *arm64*) echo "    -> 含 arm64，可原生运行" ;;
    *)       echo "    -> 仅 x86_64，需 Rosetta 2 转译运行" ;;
esac

echo ""
echo "[2] Rosetta 2 状态"
if /usr/bin/pgrep -q oahd || [ -d /Library/Apple/usr/libexec/oah ]; then
    echo "    已安装"
else
    echo "    未安装 —— 执行: softwareupdate --install-rosetta --agree-to-license"
fi

echo ""
echo "[3] 组件架构分布（是否混有 32 位 / 非 Intel 组件）"
cd "$APP" || exit 1
TOTAL=0; NON64=0
while IFS= read -r f; do
    info=$(file -b "$f" 2>/dev/null)
    case "$info" in
        *Mach-O*)
            TOTAL=$((TOTAL + 1))
            case "$info" in
                *"64-bit"*) ;;
                *) NON64=$((NON64 + 1)); echo "    32 位组件: $f" ;;
            esac
            ;;
    esac
done < <(find . -type f \( -perm -u+x -o -name "*.dylib" -o -name "*.so" \) 2>/dev/null)
echo "    Mach-O 文件总数: $TOTAL"
echo "    非 64 位组件:   $NON64"

echo ""
echo "[4] 结论"
echo "    若上面显示「仅 x86_64」且「非 64 位组件 = 0」，"
echo "    说明系统提示的「不兼容组件」指的就是整个应用为 Intel 单架构，"
echo "    并不存在某个可以单独替换的坏组件。"
echo ""
echo "    该问题无法在客户端侧修复：WindTerm 应用层闭源，"
echo "    官方未发布 arm64 包。可选路径："
echo "      a) 继续用 Rosetta 2 运行（当前可用，Apple 尚未移除）"
echo "      b) 关注上游是否发布 arm64 构建"
echo "      c) 迁移到原生 arm64 终端（WezTerm / iTerm2 / Tabby）"
