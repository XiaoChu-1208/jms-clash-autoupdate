#!/bin/sh
# jms-clash-autoupdate 一键安装（macOS + Clash Verge Rev）
#
# 两种用法，效果一样：
#
#   ① 一条命令（推荐，无需 clone）：
#      curl -fsSL https://raw.githubusercontent.com/XiaoChu-1208/jms-clash-autoupdate/main/install.sh | sh
#      然后按提示粘贴订阅链接即可，一路配好。
#
#   ② 已 clone 仓库：
#      sh install.sh                       # 全程交互
#      sh install.sh "https://你的订阅链接"  # 订阅直接给，少答一题
#
# 做的事：装两个脚本进 ~/.local/bin、写配置、配 launchd 定时任务、
# 可选装 sleepwatcher 实现「开盖即刷新」，没有可用 profile 时自动生成一份。
# 可重复运行（幂等）。

set -eu

RAW_BASE="https://raw.githubusercontent.com/XiaoChu-1208/jms-clash-autoupdate/main"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /nonexistent)"
BIN="$HOME/.local/bin"
CFG_DIR="$HOME/.config/jms-clash-autoupdate"
CFG="$CFG_DIR/config.yaml"
LABEL="com.$(id -un).jms-verge-update"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PY="/usr/bin/python3"   # macOS 自带，内置 PyYAML，永远存在
VERGE_DIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"

say() { printf '%s\n' "$*"; }

# 交互输入：管道运行（curl | sh）时 stdin 被脚本占用，必须从 /dev/tty 读。
ask() { # ask "提示" "默认值" -> 回显用户输入或默认
  _p="$1"; _d="${2:-}"
  if [ -n "$_d" ]; then printf '%s [%s]: ' "$_p" "$_d" >&2; else printf '%s: ' "$_p" >&2; fi
  if [ -r /dev/tty ]; then read -r _a < /dev/tty || _a=""; else read -r _a || _a=""; fi
  [ -z "${_a:-}" ] && _a="$_d"
  printf '%s' "$_a"
}

# 取文件：本地 clone 直接用，否则从仓库下载到目标路径。
LOCAL=0
[ -f "$SCRIPT_DIR/jms-verge-update" ] && LOCAL=1
get_file() { # get_file <仓库内相对路径> <目标绝对路径>
  if [ "$LOCAL" = 1 ] && [ -f "$SCRIPT_DIR/$1" ]; then
    cp "$SCRIPT_DIR/$1" "$2"
  else
    curl -fsSL "$RAW_BASE/$1" -o "$2"
  fi
}

say "════════════════════════════════════════════"
say " jms-clash-autoupdate 安装"
say "════════════════════════════════════════════"

# 0) 前置检查
[ -x "$PY" ] || { say "✗ 找不到 $PY（macOS 应自带）。本工具依赖系统 python3 + 内置 PyYAML。"; exit 1; }
if [ "$LOCAL" = 0 ] && ! command -v curl >/dev/null 2>&1; then
  say "✗ 需要 curl 来下载脚本。"; exit 1
fi
if [ ! -d "$VERGE_DIR" ]; then
  say "⚠ 没检测到 Clash Verge Rev 数据目录，请先安装并启动一次："
  say "    https://github.com/clash-verge-rev/clash-verge-rev"
  say "  （仍会继续安装脚本，但同步要等你有可用 profile 后才生效。）"
fi

# 1) 装脚本
mkdir -p "$BIN"
get_file "jms-verge-update" "$BIN/jms-verge-update"
get_file "jms2clash"        "$BIN/jms2clash"
chmod 0755 "$BIN/jms-verge-update" "$BIN/jms2clash"
ln -sf "$BIN/jms-verge-update" "$BIN/jmsup"     # 手动更新简称
say "✓ 已安装到 $BIN ：jms-verge-update、jms2clash、jmsup(软链)"

# 2) 订阅链接 + 配置
mkdir -p "$CFG_DIR"
SUB="${1:-${JMS_SUB_URL:-}}"
if [ -z "$SUB" ] && [ -f "$CFG" ]; then
  EXIST=$(grep -E '^sub_url:' "$CFG" 2>/dev/null | sed -E 's/^sub_url:[[:space:]]*//; s/^"//; s/"$//' || true)
  case "$EXIST" in *把这里换成*|"") ;; *) SUB="$EXIST";; esac
fi
if [ -z "$SUB" ]; then
  say ""
  say "请粘贴你的机场订阅链接（JustMySocks 的 Service 页那条 getsub.php 链接）："
  SUB=$(ask "订阅链接" "")
fi
[ -z "$SUB" ] && { say "✗ 没有订阅链接，无法继续。"; exit 1; }

[ -f "$CFG" ] && cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)" && say "  （已备份原配置）"
{
  echo "# jms-clash-autoupdate 配置（由 install.sh 生成）"
  echo "# 高级项（节点友好名 names、只留某地区 only_locations）见 config.example.yaml"
  echo "sub_url: \"$SUB\""
  echo "node_key_pattern: \"c70s\\\\d+\""
  echo "names: {}"
  echo "only_locations: []"
} > "$CFG"
chmod 600 "$CFG"
say "✓ 配置写入 $CFG（权限 600，不要公开）"

# 3) 没有可用 profile 时，自动生成一份并提示导入
NEED_IMPORT=0
if [ -f "$VERGE_DIR/profiles.yaml" ]; then
  CUR=$("$PY" - "$VERGE_DIR/profiles.yaml" <<'PY' 2>/dev/null || true
import sys,yaml
try:
    d=yaml.safe_load(open(sys.argv[1],encoding="utf-8")) or {}
    print(d.get("current") or "")
except Exception:
    print("")
PY
)
  [ -z "$CUR" ] && NEED_IMPORT=1
else
  NEED_IMPORT=1
fi
if [ "$NEED_IMPORT" = 1 ]; then
  say ""
  say "· 没检测到已选中的 profile，先用订阅生成一份 ~/Desktop/jms.yaml"
  JMS_SUB_URL="$SUB" "$PY" "$BIN/jms2clash" >/dev/null 2>&1 || true
  say "  生成完成。请在 Clash Verge 里：配置 → 新建 → 选「本地」→ 选 ~/Desktop/jms.yaml → 导入并点选它。"
fi

# 4) launchd 定时任务
say ""
INTERVAL=$(ask "定时更新间隔（秒，空跑无成本，回车=30 分钟）" "1800")
mkdir -p "$HOME/Library/LaunchAgents"
TPL_PLIST="$(mktemp)"; get_file "templates/launchd.plist.template" "$TPL_PLIST"
sed -e "s|__LABEL__|$LABEL|g" -e "s|__BIN__|$BIN|g" \
    -e "s|__HOME__|$HOME|g" -e "s|__INTERVAL__|$INTERVAL|g" \
    "$TPL_PLIST" > "$PLIST"
rm -f "$TPL_PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
say "✓ launchd 已加载（$LABEL，每 ${INTERVAL}s + 开机/登录跑一次）"

# 5) 可选：开盖即刷新（sleepwatcher）
say ""
WAKE=$(ask "要不要在「开盖/唤醒」时也自动刷新一次？(y/N)" "N")
case "$WAKE" in
  y|Y|yes|YES)
    if ! command -v brew >/dev/null 2>&1; then
      say "  ⚠ 没装 Homebrew，跳过。装了 brew 后重跑本脚本即可启用。"
    else
      SW="$(command -v sleepwatcher || true)"
      [ -z "$SW" ] && [ -x /opt/homebrew/sbin/sleepwatcher ] && SW=/opt/homebrew/sbin/sleepwatcher
      [ -z "$SW" ] && [ -x /usr/local/sbin/sleepwatcher ] && SW=/usr/local/sbin/sleepwatcher
      [ -z "$SW" ] && { say "  · 安装 sleepwatcher ..."; brew install sleepwatcher >/dev/null; }
      [ -e "$HOME/.wakeup" ] && cp "$HOME/.wakeup" "$HOME/.wakeup.bak.$(date +%Y%m%d%H%M%S)" && say "  （已备份原 ~/.wakeup）"
      TPL_WAKE="$(mktemp)"; get_file "templates/wakeup.template" "$TPL_WAKE"
      sed -e "s|__BIN__|$BIN|g" -e "s|__HOME__|$HOME|g" "$TPL_WAKE" > "$HOME/.wakeup"
      rm -f "$TPL_WAKE"; chmod +x "$HOME/.wakeup"
      brew services restart sleepwatcher >/dev/null 2>&1 || brew services start sleepwatcher >/dev/null 2>&1 || true
      say "✓ 开盖刷新已启用（sleepwatcher → ~/.wakeup）"
    fi
    ;;
  *) say "  · 跳过开盖刷新（以后想加就重跑本脚本）。" ;;
esac

# 6) 立即跑一次
say ""
say "→ 现在试跑一次 jms-verge-update ……"
"$PY" "$BIN/jms-verge-update" || say "  （若提示找不到 profile，按上面第 3 步导入后再跑 jmsup）"

# 7) PATH 提醒
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say ""
     say "⚠ $BIN 不在 PATH。把下面这行加进 ~/.zshrc 重开终端，才能直接敲 jmsup："
     say "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say ""
say "════════════════════════════════════════════"
say " 完成！日常用法："
say "   jmsup              手动同步一次"
say "   jmsup --dry-run    只预览不改"
say "   jms2clash          从订阅重新生成一份 Clash 配置"
say " 日志： ~/Library/Logs/jms-verge-update.log"
say " 卸载： curl -fsSL $RAW_BASE/uninstall.sh | sh"
say "════════════════════════════════════════════"
