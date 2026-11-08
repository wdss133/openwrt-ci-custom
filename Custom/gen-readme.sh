#!/usr/bin/env bash
# ============================================================================
# Custom/gen-readme.sh —— 按仓库实际配置生成 README.md
#
# 目的：README 永远和真实配置一致；改完 packages.seed / 设备 / workflow 后
#       重跑一次即可，不需要手工维护。fork 上游后跑 bootstrap 也会重建。
#
# 用法：bash Custom/gen-readme.sh [仓库根目录]
# ============================================================================
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

CUSTOM_DIR="Custom"
SEED="$CUSTOM_DIR/packages.seed"
CONFIG_FILE="${CONFIG_FILE:-Config/AX6-WIFI-YES.txt}"
WORKFLOW="${WORKFLOW:-.github/workflows/CUSTOM-AX6.yml}"
KEEP_MONTHS="${KEEP_MONTHS:-36}"

log() { printf '[readme] %s\n' "$*"; }

[ -f "$SEED" ] || { echo "找不到 $SEED"; exit 1; }
[ -f "$CONFIG_FILE" ] || { echo "找不到 $CONFIG_FILE"; exit 1; }
[ -f "$WORKFLOW" ] || { echo "找不到 $WORKFLOW"; exit 1; }

# --- 从 workflow 提取参数 ---
wf_val() {
	grep -E "^[[:space:]]*$1:" "$WORKFLOW" | head -n1 |
		sed -E "s/^[[:space:]]*[^:]+:[[:space:]]*//; s/[[:space:]]+#.*$//; s/''//g; s/^'//; s/'$//"
}
THEME="$(wf_val WRT_THEME)"
HOSTNAME_="$(wf_val WRT_NAME)"
SSID="$(wf_val WRT_SSID)"
WIFI_PW="$(wf_val WRT_WORD)"
LAN_IP="$(wf_val WRT_IP)"
# WRT_CONFIG 在 workflow 里写的是 ${{ matrix.CONFIG }} 模板值，
# 真实值直接取配置文件名（Config/AX6-WIFI-YES.txt -> AX6-WIFI-YES）
CONFIG_NAME="${CONFIG_NAME:-$(basename "$CONFIG_FILE" .txt)}"
CRON_LINE="$(grep -E '^[[:space:]]*- cron:' "$WORKFLOW" | head -n1 | sed -E 's/.*- cron:[[:space:]]*//')"

# --- 设备 ---
DEVICES="$(grep -E '^CONFIG_TARGET_DEVICE_.*=y' "$CONFIG_FILE" |
	sed -E 's/^CONFIG_TARGET_DEVICE_[A-Za-z0-9_]+_DEVICE_//; s/=y$//' | sed 's/^/- /')"
DEV_COUNT="$(grep -cE '^CONFIG_TARGET_DEVICE_.*=y' "$CONFIG_FILE" || true)"

# --- 新增插件（CUT-BEGIN 之前的所有 =y）---
ADDED="$(awk '/CUT-BEGIN/{exit} /^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y$/{sub(/^CONFIG_PACKAGE_/,""); sub(/=y$/,""); print "- " $0}' "$SEED")"
ADDED_COUNT="$(printf '%s\n' "$ADDED" | grep -c '^- ' || true)"

# --- 裁剪掉的包（CUT-BEGIN 之后的 is not set）---
CUT="$(awk '/CUT-BEGIN/{f=1;next} f && /^# CONFIG_PACKAGE_[A-Za-z0-9_.+-]+ is not set$/{sub(/^# CONFIG_PACKAGE_/,""); sub(/ is not set$/,""); print "- " $0}' "$SEED")"
CUT_COUNT="$(printf '%s\n' "$CUT" | grep -c '^- ' || true)"

OUT="$(mktemp)"
{
	cat <<EOF
# 红米 AX6 定制 OpenWrt 云编译

> 本项目是 [VIKINGYFY/OpenWRT-CI](https://github.com/VIKINGYFY/OpenWRT-CI) 的**二创定制版**：
> 只编红米 AX6（\`redmi_ax6-stock\`），只装自己需要的插件，每月固定编 3 次。
>
> **所有定制只新增文件、不修改上游任何文件**（唯一例外是这份 README）。
> 所以你在 GitHub 上点 **Sync fork** 拉上游更新时不会冲突，上游怎么改都不影响。
> 源码来自 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) 的 \`owrt\` 分支，
> 自带 6.18 内核、PPE 硬件 QoS、router-tool、NSS WiFi 卸载。

---

## 一、相对上游改了什么

| 项目 | 上游默认 | 本项目 |
|---|---|---|
| 编译机型 | IPQ807X 平台 **18 台**全编 | **仅 ${DEV_COUNT} 台**：$(printf '%s' "$DEVICES" | sed 's/^- //') |
| 编译配置 | \`Config/IPQ807X-WIFI-YES.txt\` | 新增 \`${CONFIG_FILE}\`（不动上游文件） |
| 触发方式 | \`Auto-Clean\` 每天触发 5 个平台全量编译 | 新增 \`CUSTOM-AX6\`，**每月 10 / 20 / 月末** 北京时间 21:00 |
| 默认主题 | \`vantage\` | **\`${THEME}\`** |
| 插件 | 上游默认清单 | **+${ADDED_COUNT} 个包**（见第四节） |
| 体积裁剪 | — | **砍掉 ${CUT_COUNT} 个包**（USB / btrfs / samba） |
| Release 保留 | 每天把 Release 全删 | **当月全留 + 最近 ${KEEP_MONTHS} 个月每月留月末**（约 3 年） |
| Release 说明 | 上游静态文案 | 自动生成：固件信息 + 两段式插件表（版本 / 上游更新日期） |
| 运行记录 | 每天全删 | 保留 3 天 |
| ccache | 每周清一次（等于每周全量重编） | 每月 1 号清 |

## 二、编译链路

\`\`\`
CUSTOM-AX6.yml（每月 10 / 20 / 月末，北京时间 21:00）
  ├─ gate job：判定今天是不是 10 号 / 20 号 / 真实月末
  │            用「明天是不是 1 号」判定，自动适配 28/29/30/31 与闰年
  │            非编译日 → 后面全部跳过，几秒结束，不占 runner
  └─ build job（needs: gate）
       └─ uses: ./.github/workflows/WRT-CORE.yml      ← 上游核心，一行未改
            ├─ 读 Config/${CONFIG_NAME}.txt + Config/GENERAL.txt 拼 .config
            ├─ Scripts/Packages.sh（拉第三方包）→ source Scripts/PRIVATE.sh
            ├─ Scripts/Settings.sh（主题 / IP / WiFi）→ cat Config/PRIVATE.txt
            ├─ make defconfig → make download → make -j
            └─ 重命名产物 → softprops/action-gh-release

Custom-Clean.yml（每天 03:00）
  └─ 当月全留 + 最近 ${KEEP_MONTHS} 个月每月只留月末那份

polish job（每次编译成功后）
  └─ 下载 .manifest → 生成两段式发布说明 → gh release edit
\`\`\`

上游的 \`Auto-Clean\` 和 \`Cache-Clean\` 已在本仓库的 Actions 页面**手动禁用**（这是仓库设置，不在文件里，所以 fork/sync 都不会重置）。
禁用后，5 个 \`*-ALL.yml\` 的 \`workflow_run\` 永远不会被触发，不会再有全平台编译。

## 三、产物命名

\`\`\`
qualcommax-ipq807x-redmi_ax6-stock-squashfs-factory-VIKINGYFY-owrt-WIFI-YES-YY.MM.DD-HH.MM.SS.ubi
qualcommax-ipq807x-redmi_ax6-stock-squashfs-sysupgrade-VIKINGYFY-owrt-WIFI-YES-YY.MM.DD-HH.MM.SS.bin
\`\`\`

| 片段 | 含义 |
|---|---|
| \`qualcommax-ipq807x-redmi_ax6-stock-squashfs-factory\` | 设备 + 镜像类型 |
| \`VIKINGYFY\` | 源码作者（\`WRT_SOURCE\` 第一段） |
| \`owrt\` | 源码分支 |
| \`WIFI-YES\` | 配置类型（从 \`WRT_CONFIG\` 名提取，所以配置文件必须保留这个后缀） |
| \`YY.MM.DD-HH.MM.SS\` | 北京时间编译时间 |

Release 的 tag 是 \`${CONFIG_NAME}-VIKINGYFY-owrt-YY.MM.DD-HH.MM.SS\`。

## 四、内置插件（新增 ${ADDED_COUNT} 个包）

$(printf '%s\n' "$ADDED")

### 裁剪掉的包（${CUT_COUNT} 个）

AX6 没有 USB 口，且不用 btrfs / samba，全部关闭：

$(printf '%s\n' "$CUT")

> 这些是在 \`Config/PRIVATE.txt\` 里用 \`is not set\` 覆盖上游 \`Config/GENERAL.txt\` 的 \`=y\`
> （\`Settings.sh\` 先 cat GENERAL 再 cat PRIVATE，后写生效）。

## 五、默认登录信息

| 项 | 值 |
|---|---|
| 地址 | \`${LAN_IP}\` |
| 密码 | 无 |
| 主机名 | \`${HOSTNAME_}\` |
| WiFi 名称 | \`${SSID}\` |
| WiFi 密码 | \`${WIFI_PW}\` |

## 六、目录结构（本项目新增的部分）

\`\`\`
Custom/
  bootstrap-fork.sh     一键定制（幂等）：生成配置、装 workflow、重建 README
  install.sh            重新 fork 后从母版仓库拉取并安装（见第八节）
  packages.seed         插件清单（唯一需要日常改的文件）
  private.sh            被装成 Scripts/PRIVATE.sh：iStore 落位 / wechatpush / 服务预启用
  gen-readme.sh         生成本 README
  gen-release-body.sh   生成 Release 说明（两段式插件表）
  release-clean.sh      Release 保留策略
  test-config.sh        自检（不联网、不编译）
  workflows/
    CUSTOM-AX6.yml      编译入口（被复制到 .github/workflows/）
    Custom-Clean.yml    Release 清理入口

Config/
  AX6-WIFI-YES.txt      只含 redmi_ax6-stock 的编译配置
  PRIVATE.txt           由 packages.seed 生成，被上游 Settings.sh 自动追加

Scripts/
  PRIVATE.sh            由 Custom/private.sh 生成，被上游 Packages.sh 自动 source
\`\`\`

上游预留的两个私有扩展入口，正是我们整套方案能"零修改"的原因：
\`Scripts/Settings.sh\` 会读 \`Config/PRIVATE.txt\`，\`Scripts/Packages.sh\` 会 source \`Scripts/PRIVATE.sh\`。

## 七、日常维护

### 加 / 删插件
\`\`\`bash
编辑 Custom/packages.seed
bash Custom/bootstrap-fork.sh
bash Custom/test-config.sh
git add -A && git commit -m "custom: 调整插件" && git push
\`\`\`

### 改编译频率
编辑 \`.github/workflows/CUSTOM-AX6.yml\` 的 \`cron\`，以及 \`gate\` job 里的 \`case "\$day"\`。

### 改设备 / 主题 / IP / WiFi
- 设备：\`Custom/bootstrap-fork.sh\` 顶部 \`DEVICE=\`，或直接改 \`${CONFIG_FILE}\`
- 主题：\`Custom/bootstrap-fork.sh\` 顶部 \`THEME=\`，或改 \`CUSTOM-AX6.yml\` 的 \`WRT_THEME\`
- IP / WiFi / 主机名：\`CUSTOM-AX6.yml\` 的 \`WRT_IP / WRT_SSID / WRT_WORD / WRT_NAME\`

## 八、重新 fork 后怎么恢复（重要）

**普通 Sync fork 不会丢东西**：因为定制全是新增文件，上游没有同名文件，合并不会冲突。

**只有"删掉仓库重新 fork"才会丢**，这时：

\`\`\`bash
git clone https://github.com/<你>/OpenWRT-CI.git
cd OpenWRT-CI
curl -fsSL https://raw.githubusercontent.com/wdss133/openwrt-ci-custom/main/install.sh | bash
git add -A && git commit -m "custom: 恢复定制" && git push
\`\`\`

\`install.sh\` 会从母版仓库 \`wdss133/openwrt-ci-custom\` 取回 \`Custom/\`，
自动生成 \`Config/AX6-WIFI-YES.txt\`、\`Config/PRIVATE.txt\`、\`Scripts/PRIVATE.sh\`、两个 workflow，
并重建本 README。最后一步是手动禁用 \`Auto-Clean\` 与 \`Cache-Clean\`（Actions 页面点一下，或用 \`gh workflow disable\`）。

---

_本 README 由 \`Custom/gen-readme.sh\` 自动生成。要改内容请改脚本或 \`Custom/packages.seed\`，勿手工大改。_
EOF
} > "$OUT"

cp "$OUT" README.md
rm -f "$OUT"
log "README.md 已生成（新增 ${ADDED_COUNT} 个包 / 裁剪 ${CUT_COUNT} 个包 / ${DEV_COUNT} 台机型）"
