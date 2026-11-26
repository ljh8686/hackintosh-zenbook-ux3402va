#!/bin/bash
# 切换 OpenCore 启动分辨率（决定 macOS 唯一可用分辨率）
# 用法: sudo sh 切换分辨率.sh 1280x800
set -e
NEW="${1:?用法: sudo sh 切换分辨率.sh <1280x800|1920x1200|2560x1600>}"
SRC="/Volumes/1401/DSH修复资料/fix-configs/config-${NEW}.plist"
[ -f "$SRC" ] || { echo "没有 $NEW 的配置模板"; ls /Volumes/1401/DSH修复资料/fix-configs/config-*.plist; exit 1; }
# 备份当前
cp /Volumes/1401/EFI/OC/config.plist "/Volumes/1401/DSH修复资料/fix-configs/config-before-$(date +%H%M%S).plist"
cp "$SRC" /Volumes/1401/EFI/OC/config.plist
echo "✅ E盘 EFI 已切换到 $NEW"
echo "现在复制到内置 ESP（否则重启不生效）:"
echo "  sudo diskutil mount disk0s1"
echo "  cp /Volumes/1401/EFI/OC/config.plist /Volumes/EFI/OC/config.plist"
echo "  sudo diskutil unmount disk0s1"
echo "然后重启，从 E 盘启动。"
