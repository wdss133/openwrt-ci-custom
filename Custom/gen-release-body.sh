#!/usr/bin/env bash
# ============================================================================
# Custom/gen-release-body.sh —— 按本项目格式重写 Release 说明
#
# 每次编译成功后由 CUSTOM-AX6.yml 的 polish job 调用：
#   1. 找到刚产出的 Release（tag 形如 AX6-WIFI-YES-VIKINGYFY-owrt-YY.MM.DD-HH.MM.SS）
#   2. 下载它的 .manifest，解析出插件版本
#   3. 对第三方插件查上游仓库最近更新日期
#   4. 生成「固件信息 / 固件版本 / 两段式插件表 / 刷机说明」，gh release edit 覆盖
#
# 环境变量：
#   REPO / GITHUB_REPOSITORY   必填
#   GH_TOKEN                   必填（读 manifest、查 API、改 Release）
#   TAG                        可选，指定 tag；缺省取最新的编译产物 Release
#   LAN_IP / HOSTNAME_ / SSID  可选，写入说明
#   KEEP_MONTHS                默认 36
# ============================================================================
set -Eeuo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
KEEP_MONTHS="${KEEP_MONTHS:-36}"
LAN_IP="${LAN_IP:-192.168.2.1}"
HOSTNAME_="${HOSTNAME_:-AX6}"
SSID="${SSID:-AX6}"

log() { printf '[release-body] %s\n' "$*"; }
die() { printf '[release-body][error] %s\n' "$*" >&2; exit 1; }

[ -n "$REPO" ] || die "需要 GITHUB_REPOSITORY"
[ -n "${GH_TOKEN:-}" ] || die "需要 GH_TOKEN"
command -v gh >/dev/null 2>&1 || die "未找到 gh CLI"
command -v jq >/dev/null 2>&1 || die "未找到 jq"

# ---------------------------------------------------------------------------
# 1) 定位 Release（排除 v1.0 这种版本 tag）
# ---------------------------------------------------------------------------
if [ -z "${TAG:-}" ]; then
	TAG="$(gh release list --repo "$REPO" --limit 30 --json tagName \
		--jq '[.[] | select(.tagName | test("-WIFI-(YES|NO)-"))] | .[0].tagName // empty')"
fi
[ -n "$TAG" ] || die "没找到形如 *-WIFI-YES-* 的 Release"
log "目标 Release: $TAG"

# ---------------------------------------------------------------------------
# 2) 从 tag 里拆出配置名、日期
# ---------------------------------------------------------------------------
DATE_RAW="$(printf '%s' "$TAG" | grep -oE '[0-9]{2}\.[0-9]{2}\.[0-9]{2}-[0-9]{2}\.[0-9]{2}\.[0-9]{2}$' || true)"
CONFIG_NAME="$(printf '%s' "$TAG" | sed -E 's/-[0-9]{2}\.[0-9]{2}\.[0-9]{2}-[0-9]{2}\.[0-9]{2}\.[0-9]{2}$//' | sed -E 's/-(VIKINGYFY|wdss133)-[^-]+$//')"
if [ -n "$DATE_RAW" ]; then
	BUILD_TIME="20$(printf '%s' "$DATE_RAW" | sed -E 's/^([0-9]{2})\.([0-9]{2})\.([0-9]{2})-(.*)$/\1-\2-\3 \4/') (UTC+8)"
else
	BUILD_TIME="$(date -u '+%Y-%m-%d %H:%M UTC')"
fi
[ -n "$CONFIG_NAME" ] || CONFIG_NAME="AX6-WIFI-YES"

# ---------------------------------------------------------------------------
# 3) 下载并解析 manifest
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MAN=""
if gh release download "$TAG" --repo "$REPO" --pattern '*.manifest' --dir "$TMP" >/dev/null 2>&1; then
	MAN="$(ls "$TMP"/*.manifest 2>/dev/null | head -n1 || true)"
fi

MANIFEST_OK=1
if [ -z "$MAN" ]; then
	MANIFEST_OK=0
	log "未找到 .manifest（可能是 TEST 模式），插件表将降级"
fi

# ---------------------------------------------------------------------------
# 4) 插件版本 / 内核版本
# ---------------------------------------------------------------------------
KVER="unknown"
if [ "$MANIFEST_OK" -eq 1 ]; then
	KVER="$(grep -E '^kernel - ' "$MAN" | head -n1 | awk '{print $3}')"
	[ -n "$KVER" ] || KVER="unknown"
fi

# 已知第三方插件 -> 上游仓库（用于查最近更新日期）
third_party_repo() {
	case "$1" in
		luci-app-easytier|easytier|easytier-noweb) echo "EasyTier/luci-app-easytier" ;;
		luci-app-zerotier|zerotier)                echo "mwarning/zerotier-openwrt" ;;
		luci-app-ddns-go|ddns-go)                  echo "sirpdboy/luci-app-ddns-go" ;;
		luci-app-store|luci-lib-taskd|luci-lib-xterm|taskd) echo "linkease/istore" ;;
		luci-app-wechatpush)                       echo "tty228/luci-app-wechatpush" ;;
		luci-theme-argon|luci-app-argon-config)    echo "sbwml/luci-theme-argon" ;;
		*) echo "" ;;
	esac
}

repo_last_push() {
	local slug="$1"
	[ -n "$slug" ] || { echo "-"; return; }
	local d
	d="$(curl -fsSL --max-time 15 -H "Authorization: token ${GH_TOKEN}" \
		"https://api.github.com/repos/${slug}" 2>/dev/null | jq -r '.pushed_at // empty' 2>/dev/null | cut -d'T' -f1)"
	[ -n "$d" ] && echo "$d" || echo "-"
}

# 新增内置（固定清单，来自 Custom/packages.seed 的前半段）
ADDED_PKGS="kmod-tun luci-app-easytier luci-app-zerotier luci-app-ddns-go luci-app-store luci-app-wechatpush luci-theme-argon luci-app-argon-config"

ADDED_TABLE=""
if [ "$MANIFEST_OK" -eq 1 ]; then
	for PKG in $ADDED_PKGS; do
		VER="$(awk -v p="$PKG" '$1==p {print $3; exit}' "$MAN")"
		if [ "$PKG" = "kmod-tun" ]; then
			[ -n "$VER" ] || VER="(随内核)"
			ADDED_TABLE="${ADDED_TABLE}| kmod-tun | ${VER} | 随内核 ${KVER} | openwrt base |\n"
			continue
		fi
		[ -n "$VER" ] || continue
		SLUG="$(third_party_repo "$PKG")"
		UPD="$(repo_last_push "$SLUG")"
		[ -n "$SLUG" ] || SLUG="-"
		ADDED_TABLE="${ADDED_TABLE}| ${PKG} | ${VER} | ${UPD} | ${SLUG} |\n"
	done
fi
[ -n "$ADDED_TABLE" ] || ADDED_TABLE="| （未采集到） | - | - | - |\n"

# 默认内置（manifest 里其余 luci-*）
DEF_TABLE=""
DEF_LIST=""
if [ "$MANIFEST_OK" -eq 1 ]; then
	while read -r NAME VER; do
		[ -n "$NAME" ] || continue
		case " $ADDED_PKGS " in *" $NAME "*) continue ;; esac
		DEF_TABLE="${DEF_TABLE}| ${NAME} | ${VER} | 随上游 feeds | openwrt feeds |\n"
		DEF_LIST="${DEF_LIST:+${DEF_LIST}、}${NAME}"
	done < <(awk 'NF>=3 && $1 ~ /^luci-(app|theme)-/ {print $1, $3}' "$MAN" 2>/dev/null || true)
fi
[ -n "$DEF_TABLE" ] || DEF_TABLE="| （未采集到） | - | - | - |\n"

# ---------------------------------------------------------------------------
# 5) 生成 body
# ---------------------------------------------------------------------------
BODY="$TMP/body.md"
{
	echo "> 📅 **编译节奏**：每月 3 次 —— **10 日、20 日、当月最后一天**，北京时间 21:00。"
	echo "> 🗂️ **保留策略**：当月全部保留；跨月后上月只留月末那一份；累计保留最近 **${KEEP_MONTHS}** 个月（约 3 年）。"
	echo "> 🧱 **定制说明**：本仓库只编红米 AX6，定制全部为新增文件，不修改上游任何文件（详见 README）。"
	echo ""
	echo "**红米 AX6 定制固件（自动编译发布）**"
	echo ""
	echo "### 📒 固件信息"
	echo "- 源码：**VIKINGYFY/immortalwrt**（分支 \`owrt\`，6.18 内核 / PPE 硬件 QoS / NSS WiFi 卸载）"
	echo "- 默认主题：**argon**"
	echo "- **本分支新添加内置**：kmod-tun、EasyTier、ZeroTier、ddns-go、iStore、wechatpush"
	echo "- **已裁剪**：USB 相关全部、btrfs、samba4（AX6 无 USB 口）"
	echo "- 🌐 默认地址：**${LAN_IP}**"
	echo "- 🔑 默认密码：无"
	echo "- 🏷️ 主机名 / WiFi：**${HOSTNAME_}** / **${SSID}**"
	echo ""
	echo "### 🧊 固件版本"
	echo "- 内核版本：**${KVER}**"
	echo "- 编译时间：${BUILD_TIME}"
	echo "- 目标机型：**redmi_ax6-stock**（squashfs: factory.ubi / sysupgrade.bin）"
	echo "- 配置：\`${CONFIG_NAME}\`"
	echo ""
	echo "### 🧩 内置插件（编译时拉取的上游版本）"
	echo ""
	echo "**🆕 本分支新添加内置**"
	echo ""
	echo "| 插件 | 版本 | 上游最近更新 | 仓库 |"
	echo "|---|---|---|---|"
	printf '%b' "$ADDED_TABLE"
	echo ""
	echo "**📦 默认内置（随镜像自带）**"
	echo ""
	if [ -n "$DEF_LIST" ]; then
		echo "共 $(printf '%s' "$DEF_LIST" | tr '、' '\n' | wc -l) 个：${DEF_LIST}"
		echo ""
	fi
	echo "| 插件 | 版本 | 上游最近更新 | 仓库 |"
	echo "|---|---|---|---|"
	printf '%b' "$DEF_TABLE"
	echo ""
	echo "### 🚀 刷机"
	echo "- 已刷过 OpenWrt / LibWrt / immortalwrt：取 \`*.bin\`，\`sysupgrade -n\` 或 LuCI「系统 → 备份/刷写固件」（首刷建议不保留配置）；"
	echo "- 原厂固件：先用 \`*.ubi\` 走 uboot / 官方恢复流程，再升级到 \`*.bin\`。"
	echo ""
	echo "---"
	echo "_本说明由 \`Custom/gen-release-body.sh\` 自动生成。_"
} > "$BODY"

log "说明已生成（manifest=$MANIFEST_OK，内核 $KVER）"
gh release edit "$TAG" --repo "$REPO" --notes-file "$BODY"
log "已更新 Release 说明: $TAG"
