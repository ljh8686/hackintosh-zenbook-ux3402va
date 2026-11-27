#!/bin/bash
# 把桌面最新的 DSDT 备份拷回内置 ESP，恢复触控板改动前的 DSDT
set -u
LATEST=$(ls -t "$HOME/Desktop"/DSDT-备份-*.aml 2>/dev/null | head -1)
if [ -z "${LATEST:-}" ]; then
  echo "桌面没有 DSDT-备份-*.aml。改用包里原厂备份 artifacts/DSDT-原始备份.aml"
  LATEST="$HOME/Documents/deepseek-harness/明日方案/artifacts/DSDT-原始备份.aml"
fi
echo "将恢复: $LATEST"
sudo fsck_msdos -y /dev/rdisk0s1 >/dev/null 2>&1
sudo diskutil mount disk0s1 >/dev/null 2>&1 || true
M=/Volumes/SYSTEM
[ -f "$M/EFI/OC/ACPI/DSDT.aml" ] || { echo "内置 ESP 未挂载到 $M"; exit 1; }
sudo cp "$LATEST" "$M/EFI/OC/ACPI/DSDT.aml" && echo "已恢复"
shasum -a256 "$M/EFI/OC/ACPI/DSDT.aml"
sudo diskutil unmount "$M" >/dev/null 2>&1 || true
echo "完成。冷关机再开机。"
