#!/bin/sh
# 卸载 jms-clash-autoupdate（不会动你的 Clash Verge 配置本身）。
set -eu

BIN="$HOME/.local/bin"
LABEL="com.$(id -un).jms-verge-update"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

say() { printf '%s\n' "$*"; }

# 1) launchd
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  say "✓ 已移除 launchd 定时任务 $LABEL"
fi

# 2) 脚本 + 软链
rm -f "$BIN/jms-verge-update" "$BIN/jms2clash" "$BIN/jmsup"
say "✓ 已移除 $BIN 下的脚本与 jmsup 软链"

# 3) 开盖刷新（只移除我们写的 ~/.wakeup；sleepwatcher 是否卸载交给你）
if [ -f "$HOME/.wakeup" ] && grep -q "jms-verge-update" "$HOME/.wakeup" 2>/dev/null; then
  rm -f "$HOME/.wakeup"
  say "✓ 已移除 ~/.wakeup（如不再需要 sleepwatcher 可自行 brew services stop sleepwatcher && brew uninstall sleepwatcher）"
fi

say ""
say "保留：~/.config/jms-clash-autoupdate/（你的订阅配置）、日志、Clash Verge 配置。"
say "如需彻底清除配置： rm -rf ~/.config/jms-clash-autoupdate"
