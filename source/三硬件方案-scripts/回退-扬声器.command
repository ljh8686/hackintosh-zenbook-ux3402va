#!/bin/bash
# 回退内置扬声器部署（恢复部署前的 config）
set -e
ESP=disk0s1
MNT=/Volumes/SYSTEM

echo "=================================================="
echo " 回退内置扬声器（恢复部署前的 config）"
echo "=================================================="
BAK="$(ls -t "$HOME/Desktop"/config-扬声器部署前-*.plist 2>/dev/null | head -1)"
if [ -z "$BAK" ]; then
  echo "⚠ 没找到桌面上的『config-扬声器部署前-*.plist』备份。"
  echo "  可用『回退-麦克风恢复config.command』或手动把 CirrusAudioFixup 的 Enabled 改回 False。"
  read -p "按回车退出..." _; exit 1
fi
echo "将恢复：$BAK"
sudo -v || exit 1
if mount | grep -q "on $MNT "; then sudo diskutil unmount "$MNT" >/dev/null 2>&1 || true; fi
if ! sudo diskutil mount $ESP >/dev/null 2>&1; then
  sudo fsck_msdos -y /dev/r"$ESP" >/dev/null 2>&1 || true
  sudo diskutil mount $ESP || { echo "无法挂载 $ESP"; exit 1; }
fi
cp "$BAK" "$MNT/EFI/OC/config.plist"
plutil -lint "$MNT/EFI/OC/config.plist"
sudo diskutil unmount "$MNT" >/dev/null 2>&1 || true
echo "✅ 已回退。请【冷启动】生效。"
read -p "按回车退出..." _
