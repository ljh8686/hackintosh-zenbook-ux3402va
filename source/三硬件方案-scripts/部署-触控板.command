#!/bin/bash
# 部署触控板 DSDT 补丁到内置 ESP（disk0s1 / 卷标 SYSTEM）
# 默认 T1（低风险）。T1 不行再试 T2。
set -u
D="$HOME/Documents/deepseek-harness/明日方案/artifacts"
echo "==================== 触控板 DSDT 部署 ===================="
echo " 1) T1 低风险：仅把 _CRS 中断从 APIC 改成 GPIO(SBFG)，引脚沿用原厂 0"
echo " 2) T2 完整  ：GPIO 引脚写 0xAF（iasl 重编译整表，改动更大/风险稍高）"
read -p "选择 [1]: " sel; sel="${sel:-1}"
if [ "$sel" = "2" ]; then SRC="$D/DSDT补丁-T2-GPIO引脚0xAF.aml"; TAG="T2"; else SRC="$D/DSDT补丁-T1-中断改GPIO.aml"; TAG="T1"; fi
[ -f "$SRC" ] || { echo "找不到补丁文件: $SRC"; exit 1; }
echo "将部署: $SRC ($TAG)"

echo "-- 清脏标记并挂载内置 ESP --"
sudo fsck_msdos -y /dev/rdisk0s1 >/dev/null 2>&1
sudo diskutil mount disk0s1 >/dev/null 2>&1 || true
M=/Volumes/SYSTEM
if [ ! -f "$M/EFI/OC/ACPI/DSDT.aml" ]; then
  echo "内置 ESP 未挂载到 $M。请先确认 disk0s1 已挂载后重试。"; exit 1
fi
BAK="$HOME/Desktop/DSDT-备份-$(date +%m%d-%H%M%S).aml"
cp "$M/EFI/OC/ACPI/DSDT.aml" "$BAK" && echo "已备份当前 DSDT -> $BAK"
sudo cp "$SRC" "$M/EFI/OC/ACPI/DSDT.aml" && echo "已写入补丁 ($TAG)"
echo "写入后校验:"; shasum -a256 "$M/EFI/OC/ACPI/DSDT.aml"
sudo diskutil unmount "$M" >/dev/null 2>&1 || true
echo
echo "完成。请【冷关机再开机】(完全关机再按下电源) 测试触控板。"
echo "若开不了机：插 1401 优盘启动，把 $BAK 拷回 内置ESP 的 EFI/OC/ACPI/DSDT.aml 即可恢复。"
