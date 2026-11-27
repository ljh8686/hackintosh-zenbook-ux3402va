#!/bin/bash
# 回退麦克风改动：把 config 还原成今晚改动前的备份（去掉 IntelSSTDMIC / 恢复原 boot-args）
set -u
D="$HOME/Documents/deepseek-harness/明日方案/artifacts"
SRC="$D/麦克风-改动前config备份.plist"
[ -f "$SRC" ] || { echo "找不到备份: $SRC"; exit 1; }
sudo fsck_msdos -y /dev/rdisk0s1 >/dev/null 2>&1
sudo diskutil mount disk0s1 >/dev/null 2>&1 || true
M=/Volumes/SYSTEM
[ -f "$M/EFI/OC/config.plist" ] || { echo "内置 ESP 未挂载到 $M"; exit 1; }
BAK="$HOME/Desktop/config-备份-$(date +%m%d-%H%M%S).plist"
cp "$M/EFI/OC/config.plist" "$BAK" && echo "当前 config 已备份 -> $BAK"
sudo cp "$SRC" "$M/EFI/OC/config.plist" && echo "已恢复改动前 config"
plutil -lint "$M/EFI/OC/config.plist"
sudo diskutil unmount "$M" >/dev/null 2>&1 || true
echo "完成。冷关机再开机。"
