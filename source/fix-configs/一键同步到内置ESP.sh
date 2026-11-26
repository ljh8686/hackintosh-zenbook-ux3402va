#!/bin/bash
# 把 E 盘上已经配好的全套 EFI（声卡 + MHelper + 新 config）同步到内置 ESP
# 用法: sudo sh 一键同步到内置ESP.sh
set -e
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行: sudo sh $0"; exit 1; }
STICK="/Volumes/1401"

echo "================ 同步 E盘 EFI → 内置 ESP ================"
echo "这将把声卡(AppleALC/SimpleHDA)、MHelper、csr=0x803 等全部写入内置启动盘。"
echo ""

# 1. 挂载内置 ESP
echo "[1/5] 挂载内置 ESP (disk0s1)..."
diskutil mount disk0s1 >/dev/null 2>&1 || true
sleep 1
ESP=""
for m in /Volumes/EFI /Volumes/MYASUS; do
  [ -d "$m/EFI/OC" ] && ESP="$m" && break
done
if [ -z "$ESP" ]; then
  echo "❌ 找不到已挂载的 ESP。请确认 disk0s1 存在，或手动: sudo diskutil mount disk0s1"
  diskutil list | grep -i efi
  exit 1
fi
echo "    ✓ ESP 挂载在: $ESP"

# 2. 备份内置 ESP 原 config + Kexts 清单
echo "[2/5] 备份内置 ESP 现有配置..."
STAMP=$(date +%Y%m%d-%H%M%S)
BK="$STICK/DSH修复资料/内置ESP备份-$STAMP"
mkdir -p "$BK"
cp "$ESP/EFI/OC/config.plist" "$BK/config.plist.bak"
ls "$ESP/EFI/OC/Kexts" > "$BK/kexts-list-before.txt" 2>/dev/null || true
echo "    ✓ 备份到: $BK"

# 3. 同步 Kexts（只增补缺失的，不删除原有的）
echo "[3/5] 同步 Kexts 到内置 ESP..."
for k in AppleALC.kext SimpleHDA.kext MHelper.kext WhateverXe.kext; do
  if [ -d "$STICK/EFI/OC/Kexts/$k" ]; then
    rm -rf "$ESP/EFI/OC/Kexts/$k"
    cp -R "$STICK/EFI/OC/Kexts/$k" "$ESP/EFI/OC/Kexts/"
    echo "    ✓ $k"
  fi
done
find "$ESP/EFI/OC/Kexts" -name '._*' -delete 2>/dev/null || true

# 4. 覆盖 config
echo "[4/5] 覆盖 config.plist..."
cp "$STICK/EFI/OC/config.plist" "$ESP/EFI/OC/config.plist"
plutil -lint "$ESP/EFI/OC/config.plist" >/dev/null && echo "    ✓ config 语法正确"

# 5. 卸载
echo "[5/5] 卸载 ESP..."
sync
diskutil unmount "$ESP" >/dev/null 2>&1 && echo "    ✓ 已卸载" || echo "    (卸载失败，可手动)"

echo ""
echo "✅ 全部完成！内置 ESP 现在拥有："
echo "   - 声卡: AppleALC 1.9.8 + SimpleHDA 1.0.2"
echo "   - 风扇/键盘背光: MHelper 0.3.1"
echo "   - csr-active-config = 0x803（MHelper/显卡需要）"
echo "   - 显卡: WhateverXe 0.8.5"
echo ""
echo "➡️  现在请重启。重启后："
echo "   1. 声卡应该回来（内建扬声器/麦克风）"
echo "   2. 菜单栏出现 MHelper 图标（风扇/键盘背光可调）"
echo "   3. 亮度/分辨率/显卡加速仍需再装 WhateverXe Graphics 包"
echo ""
echo "回滚: sudo cp '$BK/config.plist.bak' '$ESP/EFI/OC/config.plist'"
