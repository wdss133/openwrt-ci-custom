#!/usr/bin/env bash
# ============================================================================
# Custom/test-config.sh —— 定制结果自检（不联网、不编译，1 秒跑完）
# 用法：bash Custom/test-config.sh [仓库根目录]
# ============================================================================
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

CONFIG_NAME="${CONFIG_NAME:-AX6-WIFI-YES}"
DEVICE="${DEVICE:-redmi_ax6-stock}"

FAIL=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		printf '  PASS  %s\n' "$1"
	else
		printf '  FAIL  %s\n' "$1"
		FAIL=1
	fi
}

echo "== 1. 机型筛选"
N_DEV="$(grep -c '^CONFIG_TARGET_DEVICE_.*=y' "Config/${CONFIG_NAME}.txt" || true)"
check "只剩 1 个机型（当前 ${N_DEV}）" "[ \"${N_DEV}\" = 1 ]"
check "选中的是 ${DEVICE}" "grep -q 'DEVICE_${DEVICE}=y' 'Config/${CONFIG_NAME}.txt'"
check "平台是 qualcommax/ipq807x" "grep -q '^CONFIG_TARGET_qualcommax_ipq807x=y' 'Config/${CONFIG_NAME}.txt'"
check "关闭了 MULTI_PROFILE" "grep -q '^# CONFIG_TARGET_MULTI_PROFILE is not set' 'Config/${CONFIG_NAME}.txt'"

echo "== 2. 编译入口"
check "CUSTOM-AX6.yml 已安装" "[ -f .github/workflows/CUSTOM-AX6.yml ]"
check "cron 拆成 6 条单值（10/20/28/29/30/31）" "[ \"$(grep -c 'cron: 0 13 [0-9]' .github/workflows/CUSTOM-AX6.yml)\" = 6 ]"
check "Custom-Clean 带编译日兜底" "grep -q 'Maybe Trigger Build' .github/workflows/Custom-Clean.yml"
check "matrix 只有一个 CONFIG" "grep -q 'CONFIG: \[AX6-WIFI-YES\]' .github/workflows/CUSTOM-AX6.yml"
check "仍复用上游 WRT-CORE.yml" "grep -q 'uses: ./.github/workflows/WRT-CORE.yml' .github/workflows/CUSTOM-AX6.yml"
check "带 polish job 重写发布说明" "grep -q 'Polish Release' .github/workflows/CUSTOM-AX6.yml"

echo "== 3. 上游文件零修改"
check "Config/IPQ807X-WIFI-YES.txt 仍是 18 台全平台" "[ \"$(grep -c '^CONFIG_TARGET_DEVICE_.*=y' Config/IPQ807X-WIFI-YES.txt)\" -gt 10 ]"
check "QCA-ALL 的 workflow_run 原样保留" "grep -q '^  workflow_run:' .github/workflows/QCA-ALL.yml"
check "Auto-Clean 仍是上游参数" "grep -q 'delete_releases: true' .github/workflows/Auto-Clean.yml"
check "Cache-Clean 仍是每周" "grep -q 'cron: 0 20 \* \* 0' .github/workflows/Cache-Clean.yml"

echo "== 4. 保留策略"
check "Custom-Clean.yml 已安装" "[ -f .github/workflows/Custom-Clean.yml ]"
check "保留 36 个月" "grep -q \"KEEP_MONTHS: '36'\" .github/workflows/Custom-Clean.yml"

echo "== 5. 插件清单"
for PKG in kmod-tun luci-app-easytier easytier-noweb zerotier luci-app-zerotier ddns-go luci-app-ddns-go luci-app-store luci-lib-taskd luci-lib-xterm taskd luci-app-wechatpush luci-theme-argon luci-app-argon-config; do
	check "PRIVATE.txt 含 ${PKG}" "grep -q '^CONFIG_PACKAGE_${PKG}=y' Config/PRIVATE.txt"
done

echo "== 6. 裁剪项"
for PKG in kmod-usb-core kmod-usb-storage kmod-usb-net-rndis kmod-fs-btrfs luci-app-samba4; do
	check "PRIVATE.txt 关掉了 ${PKG}" "grep -q \"^# CONFIG_PACKAGE_${PKG} is not set\" Config/PRIVATE.txt"
done

echo "== 7. 私有扩展"
check "Scripts/PRIVATE.sh 已安装" "[ -f Scripts/PRIVATE.sh ]"
check "含 iStore 四包落位" "grep -q 'luci-app-store luci-lib-taskd luci-lib-xterm taskd' Scripts/PRIVATE.sh"
check "含 wechatpush 拉取" "grep -q 'tty228/luci-app-wechatpush' Scripts/PRIVATE.sh"
check "含服务预启用" "grep -q '98_custom_enable_services' Scripts/PRIVATE.sh"

echo "== 8. README"
check "README 已按本项目重写" "grep -q '二创定制版' README.md"
check "README 记录了机型" "grep -q '${DEVICE}' README.md"
check "README 记录了每月 3 次" "grep -q '每月固定编 3 次' README.md"
check "README 说明 Sync fork 不冲突" "grep -q 'Sync fork' README.md"

echo
if [ "$FAIL" -eq 0 ]; then
	echo "全部通过 ✅"
else
	echo "存在失败项 ❌"
	exit 1
fi
