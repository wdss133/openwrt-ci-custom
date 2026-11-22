#!/usr/bin/env bash
# ============================================================================
# Custom/bootstrap-fork.sh —— fork VIKINGYFY/OpenWRT-CI 后的「一键定制」
#
# 设计原则：**只新增文件，不修改上游任何文件**（唯一例外是 README.md）
#   → 在 GitHub 上点 Sync fork 拉上游更新时 100% 不冲突。
#   → 上游把 QCA-ALL / Auto-Clean / Config 怎么改都跟我们无关。
#
# 幂等：可以反复执行，结果一致。
# 用法：bash Custom/bootstrap-fork.sh [仓库根目录]
#
# 环境变量（可选）：
#   DEVICE       默认 redmi_ax6-stock
#   THEME        默认 argon
#   GH_TOKEN     设置后会顺带禁用 Auto-Clean / Cache-Clean 两个上游定时任务
#   REPO         默认从 git remote 推断，形如 owner/repo
# ============================================================================
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

DEVICE="${DEVICE:-redmi_ax6-stock}"
THEME="${THEME:-argon}"
CONFIG_NAME="${CONFIG_NAME:-AX6-WIFI-YES}"

log()  { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '::warning::%s\n' "$*"; }
die()  { printf '[bootstrap][error] %s\n' "$*" >&2; exit 1; }

[ -f .github/workflows/QCA-ALL.yml ] || die "这里不像 OpenWRT-CI 仓库根目录（找不到 .github/workflows/QCA-ALL.yml）"
[ -d Custom ]                        || die "找不到 Custom/ 目录"

# ---------------------------------------------------------------------------
# 1) 生成专用编译配置（新增文件，不碰上游 Config/IPQ807X-WIFI-YES.txt）
#    文件名必须保留 -WIFI-YES 后缀，WRT-CORE 靠它拼产物名
# ---------------------------------------------------------------------------
cat > "Config/${CONFIG_NAME}.txt" <<EOF
# ============================================================================
# 由 Custom/bootstrap-fork.sh 生成，请勿手改
# 只编 ${DEVICE}。命名必须保留 -WIFI-YES 后缀（WRT-CORE 从名字提取产物名里的 WIFI 段）
# ============================================================================
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq807x=y
CONFIG_TARGET_DEVICE_qualcommax_ipq807x_DEVICE_${DEVICE}=y

# 单机型不需要多 profile / 每设备 rootfs
# CONFIG_TARGET_MULTI_PROFILE is not set
# CONFIG_TARGET_PER_DEVICE_ROOTFS is not set
EOF
log "Config/${CONFIG_NAME}.txt → 仅 ${DEVICE}"

# ---------------------------------------------------------------------------
# 2) 插件清单 → Config/PRIVATE.txt（被上游 Scripts/Settings.sh 追加到 .config）
# ---------------------------------------------------------------------------
cp Custom/packages.seed Config/PRIVATE.txt
ADDED_N="$(awk '/CUT-BEGIN/{exit} /^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y$/' Custom/packages.seed | wc -l | tr -d ' ')"
CUT_N="$(awk '/CUT-BEGIN/{f=1;next} f && /^# CONFIG_PACKAGE_[A-Za-z0-9_.+-]+ is not set$/' Custom/packages.seed | wc -l | tr -d ' ')"
log "Config/PRIVATE.txt ← Custom/packages.seed（新增 ${ADDED_N} 个包 / 裁剪 ${CUT_N} 个包）"

# ---------------------------------------------------------------------------
# 3) 私有扩展脚本 → Scripts/PRIVATE.sh（被上游 Scripts/Packages.sh source）
# ---------------------------------------------------------------------------
cp Custom/private.sh Scripts/PRIVATE.sh
chmod +x Scripts/PRIVATE.sh
log "Scripts/PRIVATE.sh ← Custom/private.sh"

# ---------------------------------------------------------------------------
# 4) 安装两个自有 workflow（幂等覆盖）
# ---------------------------------------------------------------------------
install -m 644 Custom/workflows/CUSTOM-AX6.yml   .github/workflows/CUSTOM-AX6.yml
install -m 644 Custom/workflows/Custom-Clean.yml .github/workflows/Custom-Clean.yml
sed -i -E "s#^([[:space:]]*)WRT_THEME: .*\$#\1WRT_THEME: ${THEME}#" .github/workflows/CUSTOM-AX6.yml
sed -i -E "s#^([[:space:]]*)CONFIG: \[.*\][[:space:]]*\$#\1CONFIG: [${CONFIG_NAME}]#" .github/workflows/CUSTOM-AX6.yml
log "已安装 CUSTOM-AX6.yml / Custom-Clean.yml（主题 ${THEME}，配置 ${CONFIG_NAME}）"

# ---------------------------------------------------------------------------
# 5) 禁用两个上游定时任务（仓库设置，非文件改动，fork/sync 都不会重置）
#    禁用 Auto-Clean 就切断了「Auto-Clean → 5 个平台全量编译」的触发链；
#    禁用 Cache-Clean 避免每周清 ccache 导致每次全量重编。
# ---------------------------------------------------------------------------
REPO="${REPO:-$(git config --get remote.origin.url 2>/dev/null | sed -E 's#.*github\.com[:/]##; s#\.git$##')}"
if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1 && [ -n "$REPO" ]; then
	for WF in Auto-Clean Cache-Clean; do
		if gh workflow disable "$WF" --repo "$REPO" >/dev/null 2>&1; then
			log "已禁用上游定时任务: $WF"
		else
			warn "禁用 $WF 失败（可能已禁用，或 token 无 workflow 权限）"
		fi
	done
else
	warn "未设置 GH_TOKEN，跳过自动禁用。请到 Actions 页面手动禁用 Auto-Clean 和 Cache-Clean。"
fi

# ---------------------------------------------------------------------------
# 6) 重建 README（内容随配置自动变）
# ---------------------------------------------------------------------------
chmod +x Custom/gen-readme.sh
bash Custom/gen-readme.sh "$ROOT"
log "README.md 已按当前配置重建"

# ---------------------------------------------------------------------------
# 7) 自检
# ---------------------------------------------------------------------------
chmod +x Custom/test-config.sh
bash Custom/test-config.sh "$ROOT"

log ""
log "完成。摘要："
log "  机型：${DEVICE}（只此一台）"
log "  主题：${THEME}"
log "  配置：Config/${CONFIG_NAME}.txt"
log "  编译日：每月 10 / 20 / 月末，北京时间 21:00"
log "  改动范围：只新增文件，上游文件保持原样"
log ""
log "下一步：git add -A && git commit -m 'custom: AX6 定制' && git push"
