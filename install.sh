#!/usr/bin/env bash
# ============================================================
# noelle —— 一键安装脚本 (Arch Linux)
#
# 作用：
#   1. 从 AUR 安装上游 miyu（提供核心二进制）
#   2. 在 ~/noelle 建立独立实例（不复用 ~/.miyu）
#   3. 部署 noelle 启动器（normal / dev 模式）
#   4. 安装 fish shell 集成
#
# 用法：
#   git clone https://github.com/listvoid/noelle.git ~/noelle
#   cd ~/noelle && ./install.sh
# ============================================================
set -euo pipefail

NOELLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOELLE_HOME="$NOELLE_ROOT/.noelle"
UPSTREAM_BIN="/usr/bin/miyu"

info()  { printf '\033[1;36m[noelle]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[警告]\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------
# 0. 环境检查
# ------------------------------------------------------------
[ -f /etc/arch-release ] || die "本脚本仅支持 Arch Linux 及其衍生版"

if [ "$(id -u)" -eq 0 ]; then
    die "不要用 root 运行，用普通用户执行（AUR 构建会自动提权）"
fi

# ------------------------------------------------------------
# 1. 安装上游 miyu
# ------------------------------------------------------------
if [ -x "$UPSTREAM_BIN" ]; then
    info "已检测到上游 miyu：$("$UPSTREAM_BIN" --version 2>/dev/null | head -1)"
else
    info "未找到 miyu，开始从 AUR 安装……"
    if command -v paru >/dev/null 2>&1; then
        paru -S --needed --noconfirm miyu
    elif command -v yay >/dev/null 2>&1; then
        yay -S --needed --noconfirm miyu
    else
        die "需要 AUR 助手（paru 或 yay）。先装一个：
  sudo pacman -S --needed base-devel git
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  cd /tmp/paru && makepkg -si"
    fi
fi

# ------------------------------------------------------------
# 2. 复制核心二进制
# ------------------------------------------------------------
mkdir -p "$NOELLE_ROOT/bin"
# 上游二进制不检查自身文件名，只认 MIYU_HOME，所以可以改名
cp -f "$UPSTREAM_BIN" "$NOELLE_ROOT/bin/noelle.real"
chmod +x "$NOELLE_ROOT/bin/noelle.real"
info "核心二进制 → bin/noelle.real"

# 终端标题补丁：Miyu → NOEL（内置 logo 无法改名，标题立即数是 4 字节缓冲区上限）
if [ -f "$NOELLE_ROOT/tools/patch-title.py" ]; then
    python3 "$NOELLE_ROOT/tools/patch-title.py" \
        "$NOELLE_ROOT/bin/noelle.real" NOEL >/dev/null 2>&1 \
        && info "终端标题补丁 → NOEL" \
        || warn "标题补丁失败（上游结构可能已变），跳过"
fi

# ------------------------------------------------------------
# 3. 初始化独立数据目录（全新，不带任何旧人格/记忆）
# ------------------------------------------------------------
if [ -f "$NOELLE_HOME/config/config.jsonc" ]; then
    info "数据目录已存在，保留现有配置：$NOELLE_HOME"
else
    info "初始化全新数据目录：$NOELLE_HOME"
    MIYU_HOME="$NOELLE_HOME" "$NOELLE_ROOT/bin/noelle.real" init >/dev/null
    # 默认人格置空 + 强制走引导
    sed -i 's/"active_persona": "[^"]*"/"active_persona": ""/' \
        "$NOELLE_HOME/config/config.jsonc" 2>/dev/null || true
    sed -i 's/"oobe_done": true/"oobe_done": false/' \
        "$NOELLE_HOME/config/config.jsonc" 2>/dev/null || true
fi

# 关闭内置 ASCII banner（MIYU 字形是编译期常量，改不了，改用 assets/banner.txt）
sed -i 's/"banner": true/"banner": false/' \
    "$NOELLE_HOME/config/config.jsonc" 2>/dev/null || true
info "已关闭内置 banner，改用 NOELLE 字形"

# ------------------------------------------------------------
# 4. 部署启动器
# ------------------------------------------------------------
chmod +x "$NOELLE_ROOT/bin/noelle"
mkdir -p "$NOELLE_ROOT/.local/bin"
cat > "$NOELLE_ROOT/.local/bin/noelle" <<'WRAPPER'
#!/bin/bash
exec "$HOME/noelle/bin/noelle" "$@"
WRAPPER
chmod +x "$NOELLE_ROOT/.local/bin/noelle"
info "启动器 → bin/noelle、.local/bin/noelle"

# ------------------------------------------------------------
# 5. 安装 shell 集成
# ------------------------------------------------------------
if command -v fish >/dev/null 2>&1; then
    conf="$HOME/.config/fish/conf.d"
    mkdir -p "$conf"
    cp -f "$NOELLE_ROOT/noelle.fish" "$conf/noelle.fish"
    info "fish hook → $conf/noelle.fish"
else
    warn "未安装 fish，跳过 shell 集成（可自行 pacman -S fish）"
fi

# ------------------------------------------------------------
# 完成
# ------------------------------------------------------------
cat <<EOF

────────────────────────────────────────────────────────
 安装完成

   首次使用：  noelle normal       # 自动进入新手引导
   设置人格：  noelle oobe         # 重跑引导
   普通模式：  noelle normal
   开发模式：  noelle dev          # 无人格极简编码形态
   单次提问：  noelle ask "问题"
   路径信息：  noelle paths

 数据目录：$NOELLE_HOME
 上游项目：https://github.com/SHORiN-KiWATA/miyu-agent
────────────────────────────────────────────────────────
EOF
