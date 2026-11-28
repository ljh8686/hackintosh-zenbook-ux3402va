#!/bin/bash
# ===== DSH 黑苹果一键修复（集显 / 声卡 / ASUS 控制台）=====
# 机器：ASUS Zenbook UX3402VA / i9-13900H / Iris Xe 0xA7A0 / macOS 26.7.3(25G342)
# 每一项都可单独执行、单独回退；需要管理员密码的操作会弹窗/提示。
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

banner(){
  clear
  echo "=================================================================="
  echo "        DSH 黑苹果一键修复  ——  集显 / 声卡 / ASUS 控制台"
  echo "=================================================================="
}

state(){
  echo "---- 当前状态快照 ----"
  echo -n "GPU: "; system_profiler SPDisplaysDataType 2>/dev/null | awk '/Chipset Model/{m=$0} /VRAM \(Total\)/{v=$0} END{print m" "v}' | sed 's/  */ /g'
  echo -n "HookCase/TGL kext: "; kextstat 2>/dev/null | grep -Eo 'org.smichaud.HookCase|com.apple.driver.AppleIntelTGLGraphics[A-Za-z]*' | sort -u | tr '\n' ' '; echo
  echo -n "CirrusAudioFixup: "; [ -e /Library/Extensions/CirrusAudioFixup.kext ] && echo "已安装" || echo "未安装"
  echo -n "ASUS控制台.app: "; [ -e "/Applications/ASUS控制台.app" ] && echo "已安装" || echo "缺失"
  echo -n "swiftc: "; swiftc --version >/dev/null 2>&1 && echo "可用" || echo "不可用(需 xcode-select --install)"
  echo "----------------------"
}

menu(){
  banner; state
  cat <<'EOF'

  [1] 修复集显 —— 恢复 NootedGreen 系统驱动栈（需管理员密码，之后重启生效）
  [2] 修复声卡 —— 安装 CS35L41 内置扬声器驱动（⚠ 有极小损伤风险，先调低音量）
  [3] 声卡回退 —— 卸载 CS35L41 扬声器驱动（恢复安全状态）
  [4] 安装 ASUS 控制台 —— 用最新源码编译并安装（需命令行工具 swiftc）
  [5] 诊断 —— 输出当前 GPU/声卡/控制台状态与相关 kext（只读）
  [6] 全部执行 —— 依次执行 1、4（不含有风险的声卡）
  [0] 退出
EOF
  echo
  read -r -p "请选择 [0-6]: " c
  case "$c" in
    1) bash "$DIR/lib/restore-gpu.sh"; echo; read -r -p "按回车返回菜单..." _ ; menu;;
    2) echo "⚠ 请先把系统音量调到 1~2 格。"; read -r -p "确认继续安装内置扬声器驱动? (输入 y 继续): " ok
       [ "$ok" = "y" ] && bash "$DIR/lib/install-speaker.sh"; read -r -p "按回车返回菜单..." _ ; menu;;
    3) bash "$DIR/lib/rollback-speaker.sh"; read -r -p "按回车返回菜单..." _ ; menu;;
    4) bash "$DIR/lib/build-asus-console.sh"; read -r -p "按回车返回菜单..." _ ; menu;;
    5) bash "$DIR/lib/diagnose.sh" | tee "$DIR/诊断输出/诊断-$(date +%Y%m%d-%H%M%S).txt"; read -r -p "按回车返回菜单..." _ ; menu;;
    6) bash "$DIR/lib/restore-gpu.sh"; bash "$DIR/lib/build-asus-console.sh"; read -r -p "按回车返回菜单..." _ ; menu;;
    0) exit 0;;
    *) menu;;
  esac
}
menu
