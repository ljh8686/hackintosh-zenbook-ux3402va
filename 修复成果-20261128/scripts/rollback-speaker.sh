#!/bin/bash
# 回退声卡(内置扬声器)：移除 CirrusAudioFixup 并重建 AuxKC
set -u
if [ "$(id -u)" -ne 0 ]; then exec sudo /bin/bash "$0" "$@"; fi
say(){ printf '\n\033[1;33m== %s ==\033[0m\n' "$*"; }
say "移除 /Library/Extensions/CirrusAudioFixup.kext"
rm -rf /Library/Extensions/CirrusAudioFixup.kext
say "重建 AuxKC"
kmutil create -n aux -z -V release -r /Library/Extensions --allow-missing-kdk \
  -B /System/Library/KernelCollections/BootKernelExtensions.kc \
  -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
  -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --no-authentication \
  && echo "AuxKC 重建成功" || echo "!! kmutil create 返回非零"
echo "完成，请冷启动。"
