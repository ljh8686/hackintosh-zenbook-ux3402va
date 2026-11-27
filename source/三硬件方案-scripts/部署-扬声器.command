#!/bin/bash
# 部署内置扬声器驱动（CirrusAudioFixup，CS35L41 / 板 1043:16A3）
# 两个调音来源可选，全程有备份，可回退。
set -e
ESP=disk0s1
MNT=/Volumes/SYSTEM
ART="$(cd "$(dirname "$0")/../artifacts" && pwd)"

echo "=================================================="
echo " 部署内置扬声器（CirrusAudioFixup / CS35L41）"
echo "=================================================="
echo "这台机器的板子(1043:16A3)没有原厂调音数据，只能借用同门华硕机型。"
echo "可选："
echo "  1) UM3402Y（同款 Zenbook 14 机身/喇叭，推荐，相对更安全）  [默认]"
echo "  2) ROG Strix G16（立体声齐全，但不同机身喇叭）"
read -p "选择 [1]: " sel; sel="${sel:-1}"
if [ "$sel" = "2" ]; then
  SRC="$ART/Cirrus扬声器-CirrusAudioFixup-ROG16.kext"; TAG="ROG16"
else
  SRC="$ART/Cirrus扬声器-CirrusAudioFixup-UM3402Y.kext"; TAG="UM3402Y"
fi
[ -d "$SRC" ] || { echo "找不到 $SRC"; exit 1; }
echo "将使用：$TAG ($SRC)"
echo
echo "⚠ 安全提示：无论哪版，保护系数都不是这块喇叭本来的。"
echo "  部署前请把系统音量调到很低（1~2 格 / 约 10%）；重启后先用很小音量试。"
echo "  出问题双击「回退-扬声器.command」恢复。"
read -p "已了解并把音量调很低？输入 y 继续：" a
[ "$a" = "y" ] || { echo "已取消。"; exit 1; }

sudo -v || { echo "需要管理员权限"; exit 1; }
if mount | grep -q "on $MNT "; then sudo diskutil unmount "$MNT" >/dev/null 2>&1 || true; fi
if ! sudo diskutil mount $ESP >/dev/null 2>&1; then
  echo "挂载失败，尝试修复文件系统脏标记..."
  sudo fsck_msdos -y /dev/r"$ESP" >/dev/null 2>&1 || true
  sudo diskutil mount $ESP || { echo "无法挂载 $ESP"; exit 1; }
fi
[ -d "$MNT/EFI/OC" ] || { echo "ESP 未挂载到 $MNT"; exit 1; }

CFG="$MNT/EFI/OC/config.plist"
BAK="$HOME/Desktop/config-扬声器部署前-$(date +%Y%m%d-%H%M%S).plist"
cp "$CFG" "$BAK"; echo "已备份原 config -> $BAK"

echo "替换 CirrusAudioFixup.kext ($TAG)..."
rm -rf "$MNT/EFI/OC/Kexts/CirrusAudioFixup.kext"
cp -R "$SRC" "$MNT/EFI/OC/Kexts/CirrusAudioFixup.kext"

echo "在 config 中启用 CirrusAudioFixup（Kernel Add Enabled=True）..."
python3 - "$CFG" <<'PY'
import sys, plistlib
p=sys.argv[1]
with open(p,'rb') as f: d=plistlib.load(f)
ka=d['Kernel']['Add']; found=False
for e in ka:
    if 'CirrusAudioFixup' in e.get('BundlePath',''):
        e['Enabled']=True; e['Arch']=e.get('Arch','x86_64')
        if 'MinKernel' not in e: e['MinKernel']='25.0.0'
        found=True
if not found:
    ka.append({'Arch':'x86_64','BundlePath':'CirrusAudioFixup.kext','Enabled':True,'MaxKernel':'','MinKernel':'25.0.0','Comment':'CS35L41 speaker 16A3'})
with open(p,'wb') as f: plistlib.dump(d,f)
print("Kernel Add: CirrusAudioFixup Enabled=True")
PY
plutil -lint "$CFG"

sudo diskutil unmount "$MNT" >/dev/null 2>&1 || true
echo
echo "✅ 部署完成（$TAG）。请【冷启动】（完全关机再开机），小音量试。"
echo "   异常就双击『回退-扬声器.command』。"
read -p "按回车退出..." _
