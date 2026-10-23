#!/usr/bin/env bash
# ============================================================
# noelle —— 卸载脚本
# 只删除 noelle 自己的部署，不触碰上游 miyu 与 ~/.miyu
# ============================================================
set -uo pipefail

NOELLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOELLE_HOME="$NOELLE_ROOT/.noelle"

echo "将删除："
echo "  · $NOELLE_HOME （含所有会话、记忆、API Key）"
echo "  · ~/.config/fish/conf.d/noelle.fish"
echo "  · $NOELLE_ROOT/bin/noelle.real"
echo
read -rp "确认？[y/N] " ans
case "$ans" in
    y|Y) ;;
    *) echo "已取消"; exit 0 ;;
esac

# 1. 停掉 noelle 的 daemon（必须用带 MIYU_HOME 的启动器）
if [ -x "$NOELLE_ROOT/bin/noelle" ]; then
    "$NOELLE_ROOT/bin/noelle" daemon stop 2>/dev/null && echo "✓ daemon 已停止"
fi

# 2. 移除 shell hook
if [ -f "$HOME/.config/fish/conf.d/noelle.fish" ]; then
    rm -f "$HOME/.config/fish/conf.d/noelle.fish"
    echo "✓ 已移除 fish hook"
fi

# 3. 移除数据目录与二进制
rm -rf "$NOELLE_HOME" && echo "✓ 已移除数据目录"
rm -f "$NOELLE_ROOT/bin/noelle.real" && echo "✓ 已移除核心二进制"

echo
echo "卸载完成。如需彻底删除：rm -rf $NOELLE_ROOT"
