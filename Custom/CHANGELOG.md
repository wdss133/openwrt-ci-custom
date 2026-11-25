# 变更记录

> 固件 Release 页只放固件，版本变更统一记在这里。
> 本文件是新增文件，`Sync fork` 不会冲突；重新 fork 会丢，但母版仓库 `openwrt-ci-custom` 有同一份。

---

## v2.0 — 2026-11-25

**清理挪进编译流程，版本记录迁出 Releases**

- 新增 `trim` job（`CUSTOM-AX6.yml`）：Gate 判定通过后、`build` 之前执行 `release-clean.sh`。
  `build` 改成 `needs: [gate, trim]`，清理失败用 `continue-on-error` 兜住，不阻断编译。
- 效果：清理严格跟着打包走，**一个月恰好 3 次**（10 号 / 20 号 / 月末），不再有独立的定时清理。
- `Custom-Clean` 只剩兜底，cron 收敛到 3 条：`0 19 1`、`0 19 11`、`0 19 21`（编译日次日 03:00）。
- 版本更新记录从 GitHub Releases 迁到本文件，`v1.0` ~ `v1.9` 的 Release 与 tag 已删除。

## v1.9 — 2026-11-25

**清理降频 + 去重改 24 小时窗口**

- `Custom-Clean` 从每天 03:00 改为两条时间线（清理 6 次/月 + 兜底 3 次/月）。
- Gate 去重从「意图日期匹配」升级成「最近 24 小时窗口」：
  兜底补编的 tag 用当天日期，cron 延迟到次日时意图日期是前一天，按日期比对会漏判。

## v1.8 — 2026-11-22

**固化需求基线**

- 把散落在多轮沟通里的定制要求收敛成 R1~R10，写成文档（仅本地，不上传仓库）。
- 仓库侧只保留脚本与模板。

## v1.7 — 2026-11-22

**编译日去重**

- Gate 在 `schedule` 分支加去重：同一编译日已有产物就 `skip_already_built`。
- 修的是 11-20 编两次的问题（兜底 08:59 + cron 延迟到 21 号 04:51）。

## v1.6 — 2026-11-22

**合并上游更新**

- 上游 `6a66469` 只改了 README 一条推广链接，用 `git merge -X ours upstream/main` 合并。
- 验证：13 个定制文件全在、43 项自检通过。

## v1.5 — 2026-11-11

**修复定时从不触发**

- 根因：列表式 day-of-month（`10,20,28,29,30,31`）不被 GitHub 调度器注册；
  同仓库的 `0 19 * * *` 却能触发。
- 修复：拆成 6 条单值 cron；`Custom-Clean` 增加编译日兜底补编。

## v1.4 — 2026-11-10

**修复 Custom-Clean 空数组崩溃**

- `release-clean.sh` 第 63 行 `bad array subscript`：
  tag 结构是 `<配置>-WIFI-YES-<作者>-<分支>-日期`，case 模式漏了中间两段，一个都匹配不到。
- 修复：case 只按前缀筛、日期交给正则；改用普通变量计数（`set -u` 下空关联数组取长度会报 unbound）。

## v1.3 — 2026-11-08

**补回 PassWall / 动态 DNS / frp / uHTTPd，去掉 HomeProxy**

- 照抄 `openwrt-ci-roc` 的 `configs/General.config` 取舍：
  PassWall 只开 Nftables 透明代理 + Xray + Geoview，其余 15 个 INCLUDE 全关。
- `luci-app-homeproxy` 设 `is not set`。

## v1.2 — 2026-11-08

**修复手动触发时 Gate 摘要误显示 skip**

- 延迟回退逻辑对 `workflow_dispatch` 也生效，白天手动跑会被回退到昨天。
- 修复：回退只在 `EVENT == schedule`；手动直接 `kind=manual`。

## v1.1 — 2026-11-08

**零修改上游 + 自动 README / Release 说明**

- 定制全部收敛成新增文件：`Config/AX6-WIFI-YES.txt`、`Custom/`、两个 workflow、`Config/PRIVATE.txt`、`Scripts/PRIVATE.sh`。
- 上游的 `Config/IPQ807X-WIFI-YES.txt`、5 个 `*-ALL.yml`、`Auto-Clean`、`Cache-Clean` 全部还原原样，
  改用 Actions 页面禁用。
- 新增 `gen-readme.sh` / `gen-release-body.sh` / `install.sh`。

## v1.0 — 2026-11-08

**首个可用版本**

- 只编 `redmi_ax6-stock`；每月 10 / 20 / 月末 21:00；Gate 用「明天是不是 1 号」判月末。
- 发布 `-latest` + `-YYYYMM10` / `-YYYYMM20` / `-YYYYMM`；跨月只留月末，保留 36 个月。
- 剪掉 30 个 `kmod-usb-*`、`kmod-fs-btrfs`、`luci-app-samba4`（后续版本继续深挖到 DEFAULT_PACKAGES 与内核符号层）。