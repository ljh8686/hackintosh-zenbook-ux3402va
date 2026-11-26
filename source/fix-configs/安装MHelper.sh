#!/bin/bash
# 一键把 MHelper.kext 装进内置 ESP 并同步 E 盘配置（需 sudo）
# 用法: sudo sh 安装MHelper.sh
set -e
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行: sudo sh $0"; exit 1; }
STICK_MOUNT="/Volumes/1401"

echo "[1/4] 挂载内置 ESP..."
diskutil mount disk0s1 >/dev/null 2>&1 || true
sleep 1
EFI_MNT=""
for m in /Volumes/EFI /Volumes/MYASUS; do
  [ -d "$m/EFI/OC" ] && EFI_MNT="$m" && break
done
[ -n "$EFI_MNT" ] || { echo "找不到已挂载的 ESP，请手动挂载 disk0s1 后重试"; diskutil list; exit 1; }
echo "    ESP: $EFI_MNT"

echo "[2/4] 备份内置 ESP 现有 config..."
cp "$EFI_MNT/EFI/OC/config.plist" "$STICK_MOUNT/DSH修复资料/config-builtinESP-before-mhelper-$(date +%Y%m%d-%H%M%S).plist"

echo "[3/4] 拷贝 MHelper.kext 到内置 ESP..."
rm -rf "$EFI_MNT/EFI/OC/Kexts/MHelper.kext"
cp -R "$STICK_MOUNT/EFI/OC/Kexts/MHelper.kext" "$EFI_MNT/EFI/OC/Kexts/"
find "$EFI_MNT/EFI/OC/Kexts" -name '._*' -delete 2>/dev/null || true

echo "[4/4] 同步 config.plist（E盘已配好 MHelper）..."
cp "$STICK_MOUNT/EFI/OC/config.plist" "$EFI_MNT/EFI/OC/config.plist"
sync

echo ""
echo "✅ 完成。MHelper.kext 已装入内置 ESP 并写入 config。"
echo "   现在请重启。重启后："
echo "   - 菜单栏右上角会出现 MHelper 图标"
echo "   - 可调风扇、键盘背光、性能模式"
echo ""
echo "   如果重启后 MHelper 图标没出现，检查 E 盘是否作为启动盘（F12 选 1401）。"
echo "   回滚: sudo cp \"$STICK_MOUNT/DSH修复资料/config-builtinESP-before-mhelper-*.plist\" \"$EFI_MNT/EFI/OC/config.plist\""
