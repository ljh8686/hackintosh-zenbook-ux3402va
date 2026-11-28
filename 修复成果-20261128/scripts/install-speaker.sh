#!/bin/bash
# 修复声卡(内置扬声器)：安装 CirrusAudioFixup kext（CS35L41 智能功放，板 1043:16A3，调音借用同门 ASUS UM3402Y）
# ⚠ 风险：调音系数非本机原厂，极小概率损伤喇叭。务必先把系统音量调到 1~2 格，异常立即运行 rollback-speaker.sh。
set -u
if [ "$(id -u)" -ne 0 ]; then exec sudo /bin/bash "$0" "$@"; fi

BASE="$(cd "$(dirname "$0")/.." && pwd)"
KEXT="$BASE/payload/CirrusAudioFixup.kext"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/Users/Shared/CirrusAudioFixup-备份-$STAMP"
mkdir -p "$BACKUP"

say(){ printf '\n\033[1;35m== %s ==\033[0m\n' "$*"; }
[ -d "$KEXT" ] || { echo "缺少 payload/CirrusAudioFixup.kext"; exit 1; }

say "1/4 备份现有同名 kext"
[ -e /Library/Extensions/CirrusAudioFixup.kext ] && mv /Library/Extensions/CirrusAudioFixup.kext "$BACKUP/"

say "2/4 安装到 /Library/Extensions"
cp -R "$KEXT" /Library/Extensions/
chown -R root:wheel /Library/Extensions/CirrusAudioFixup.kext
chmod -R go-w /Library/Extensions/CirrusAudioFixup.kext

say "3/4 重建 AuxKC"
kmutil create -n aux -z -V release -r /Library/Extensions --allow-missing-kdk \
  -B /System/Library/KernelCollections/BootKernelExtensions.kc \
  -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
  -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --no-authentication \
  && echo "AuxKC 重建成功" || echo "!! kmutil create 返回非零"

say "4/4 完成"
echo "备份：$BACKUP"
echo "请【冷启动】后，用【小音量】播放测试内置扬声器。异常请运行 rollback-speaker.sh。"
