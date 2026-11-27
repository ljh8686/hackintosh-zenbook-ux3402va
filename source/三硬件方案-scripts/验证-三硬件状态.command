#!/bin/bash
# 三硬件修复结果自检（只读，不修改任何东西，不需要 sudo）
# 用法：每次冷启动后双击本脚本，看四项状态。
set +e
echo "=================================================="
echo "  三硬件修复 状态自检  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

echo
echo "[1] 麦克风驱动 IntelSSTDMIC（内置 Intel 智音 SST 数字麦）:"
if kmutil showloaded 2>/dev/null | grep -qi IntelSSTDMIC; then
  echo "  ✅ 已加载 —— 请打开【语音备忘录】录 5 秒，看有没有波形/能否回放出声"
else
  echo "  ❌ 未加载（麦克风驱动没生效，跑 回退-麦克风 或告诉我）"
fi

echo
echo "[2] 扬声器驱动 CirrusAudioFixup（CS35L41 杜比功放）:"
if kmutil showloaded 2>/dev/null | grep -qi CirrusAudioFixup; then
  echo "  ✅ 已加载"
else
  echo "  ⚠ 未加载（要么还没部署，要么被系统拒了）"
fi
ioreg -lw0 -p IOService -r -c CirrusAudioFixup 2>/dev/null \
  | grep -E 'Cirrus_(Driver_Verdict|Detected_Amplifiers|Bus|Candidate_Status|Attach_Latest_Reason|Board_Metadata_Reason|Board_Authorized)' \
  | sed 's/^ *//' | head -12
echo "  —— Driver_Verdict=READY_DSP 且小音量有声音=成功；仍 BOARD_METADATA_REJECTED=这版没通过"

echo
echo "[3] 触控板 VoodooI2C（ASUE120C）:"
ioreg -lw0 -p IOService -r -c VoodooI2CDeviceNub 2>/dev/null | grep -E '"(name|IOClass|IOProviderClass)"' | head -4
if kmutil showloaded 2>/dev/null | grep -qiE 'VoodooI2CHID|VoodooInput'; then
  echo "  ✅ VoodooI2CHID/Input 已加载 —— 触控板应该能动了（试轻点/滑动）"
else
  echo "  ❌ VoodooI2CHID/Input 未加载 —— 触控板仍未接通（nub 没匹配）"
fi
echo "  当前 TPD0 中断描述:"
ioreg -rn TPD0 2>/dev/null | grep -E 'IOInterruptSpecifiers' | head -1

echo
echo "[4] 当前音频设备（默认输入/输出）:"
system_profiler SPAudioDataType 2>/dev/null \
  | grep -E '^ {8}[^ ].*:$|Default (Input|Output) Device|Input Source|Transport' | head -24

echo
echo "=================================================="
echo " 说明：麦克风=重点看语音备忘录波形；扬声器=小音量试；"
echo "       触控板=看 [3] 是否 ✅；任何一项不行就双击对应『回退』脚本。"
echo "=================================================="
read -p "按回车关闭..." _
