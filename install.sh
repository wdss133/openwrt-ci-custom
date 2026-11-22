#!/usr/bin/env bash
# ============================================================================
# install.sh —— 重新 fork 之后的一键恢复
#
# 用法（在刚 fork 下来的 OpenWRT-CI 仓库根目录执行）：
#   curl -fsSL https://raw.githubusercontent.com/wdss133/openwrt-ci-custom/main/install.sh | bash
#
# 它会：
#   1) 从母版仓库 wdss133/openwrt-ci-custom 取回 Custom/ 目录
#   2) 跑 Custom/bootstrap-fork.sh（生成配置 / 装 workflow / 重建 README / 自检）
#
# 环境变量：
#   MOTHER   母版仓库，默认 wdss133/openwrt-ci-custom
#   BRANCH   母版分支，默认 main
#   GH_TOKEN 设置后会顺带禁用 Auto-Clean / Cache-Clean
# ============================================================================
set -Eeuo pipefail

MOTHER="${MOTHER:-wdss133/openwrt-ci-custom}"
BRANCH="${BRANCH:-main}"

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install][error] %s\n' "$*" >&2; exit 1; }

# 必须在 OpenWRT-CI 仓库根目录执行
[ -f .github/workflows/QCA-ALL.yml ] || die "请先 cd 到 OpenWRT-CI 仓库根目录再执行"
command -v curl >/dev/null 2>&1 || die "需要 curl"
command -v tar  >/dev/null 2>&1 || die "需要 tar"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "从 ${MOTHER}@${BRANCH} 拉取定制层"
curl -fsSL "https://codeload.github.com/${MOTHER}/tar.gz/refs/heads/${BRANCH}" -o "$TMP/m.tar.gz" \
	|| die "下载母版仓库失败，检查地址或网络"
tar -xzf "$TMP/m.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -mindepth 1 -type d | head -n1)"
[ -d "${SRC}/Custom" ] || die "母版仓库里没有 Custom/ 目录"

rm -rf ./Custom
cp -a "${SRC}/Custom" ./Custom
chmod +x ./Custom/*.sh
log "Custom/ 已就位"

bash ./Custom/bootstrap-fork.sh "$PWD"

log ""
log "恢复完成。检查一下 git status，然后："
log "  git add -A && git commit -m 'custom: 恢复 AX6 定制' && git push"
