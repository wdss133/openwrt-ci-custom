#!/usr/bin/env bash
# ============================================================================
# Custom/release-clean.sh —— Release 保留策略
#
# 保留：
#   - 当月所有 Release（每月 3 次，最多 3 个）
#   - 最近 KEEP_MONTHS 个月里，每个月的「最后一次」（即月末那次）
# 删除其余本项目的 Release（tag 形如 *-WIFI-YES-YY.MM.DD-HH.MM.SS）。
#
# 效果：跨月后上月只留月末那一份，累计保留 KEEP_MONTHS 个月（默认 36 = 3 年）。
#
# 环境变量：
#   REPO / GITHUB_REPOSITORY   必填
#   KEEP_MONTHS                默认 36
#   DRY_RUN=true               只打印不删除
# ============================================================================
set -Eeuo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
KEEP_MONTHS="${KEEP_MONTHS:-36}"
DRY_RUN="${DRY_RUN:-false}"

log() { printf '[release-clean] %s\n' "$*"; }
die() { printf '[release-clean][error] %s\n' "$*" >&2; exit 1; }

[ -n "$REPO" ] || die "需要 GITHUB_REPOSITORY（或 REPO）"
command -v gh >/dev/null 2>&1 || die "未找到 gh CLI"

NOW_YM="$(date -u +%Y%m)"

mapfile -t TAGS < <(gh release list --repo "$REPO" --limit 1000 --json tagName --jq '.[].tagName')
log "共 ${#TAGS[@]} 个 Release，当月 ${NOW_YM}，保留 ${KEEP_MONTHS} 个月"

declare -A LAST_OF_MONTH   # ym -> 该月最后一次的 tag
declare -A CUR_MONTH       # 当月 tag 集合
declare -A SEEN_MONTH      # 去重用
SEEN_COUNT=0               # 用普通变量计数：set -u 下对空关联数组取长度会报 unbound

for t in "${TAGS[@]}"; do
	# 只认本项目产物。注意 tag 结构是：
	#   <配置>-WIFI-YES-<源码作者>-<分支>-YY.MM.DD-HH.MM.SS
	# 中间还有作者/分支两段，所以这里只按 -WIFI-YES- 前缀筛，日期交给下面的正则校验。
	case "$t" in
		*-WIFI-YES-*|*-WIFI-NO-*) ;;
		*) continue ;;
	esac
	[[ "$t" =~ -([0-9]{2})\.([0-9]{2})\.([0-9]{2})-([0-9]{2})\.([0-9]{2})\.([0-9]{2})$ ]] || continue
	ym="20${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
	if [ "$ym" = "$NOW_YM" ]; then
		CUR_MONTH["$t"]=1
	fi
	prev="${LAST_OF_MONTH[$ym]:-}"
	# 同月 tag 前缀一致，日期段字典序 == 时间序
	if [ -z "$prev" ] || [[ "$t" > "$prev" ]]; then
		LAST_OF_MONTH["$ym"]="$t"
	fi
	SEEN_MONTH["$ym"]=1
	SEEN_COUNT=1
done

# 最近 KEEP_MONTHS 个月（按 ym 倒序）
# 防御：一个可识别的固件 Release 都没有时，YMS 会拿到一个空字符串，
# 后面 LAST_OF_MONTH[""] 会触发 bad array subscript，这里提前退出。
if [ "$SEEN_COUNT" -eq 0 ]; then
	log "没有可识别的固件 Release（形如 *-WIFI-YES-...），跳过清理"
	exit 0
fi

mapfile -t YMS < <(printf '%s\n' "${!SEEN_MONTH[@]}" | sort -r | head -n "$KEEP_MONTHS")

declare -A KEEP
for ym in "${YMS[@]}"; do
	[ -n "$ym" ] || continue
	KEEP["${LAST_OF_MONTH[$ym]}"]=1
done
for t in "${!CUR_MONTH[@]}"; do
	KEEP["$t"]=1
done

log "保留集合（${#KEEP[@]} 个）："
printf '  %s\n' "${!KEEP[@]}" | sort

DELETED=0
for t in "${TAGS[@]}"; do
	[ -n "${KEEP[$t]:-}" ] && continue
	case "$t" in
		*-WIFI-YES-*|*-WIFI-NO-*) ;;
		*) continue ;;
	esac
	if [ "$DRY_RUN" = "true" ]; then
		log "DRY_RUN 将删除: $t"
	else
		log "删除: $t"
		gh release delete "$t" --repo "$REPO" --yes --cleanup-tag || log "删除失败，跳过: $t"
	fi
	DELETED=$((DELETED + 1))
done

log "完成，共处理 ${DELETED} 个"
