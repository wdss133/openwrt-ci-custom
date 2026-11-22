# Custom/ —— AX6 定制层

fork `VIKINGYFY/OpenWRT-CI` 后，这一个目录 + 跑一次 `bootstrap-fork.sh` 就把整套定制装好。
核心逻辑（`WRT-CORE.yml`、`Scripts/Packages.sh`、`Scripts/Settings.sh`）**一行都不改**。

## 目录

| 文件 | 作用 |
|---|---|
| `bootstrap-fork.sh` | 一键定制（幂等）。改设备清单、写插件清单、装两个 workflow、改造 Auto-Clean |
| `packages.seed` | 插件清单（`CONFIG_PACKAGE_xxx=y`），会被复制成 `Config/PRIVATE.txt` |
| `private.sh` | 会被复制成 `Scripts/PRIVATE.sh`，负责 iStore 落位、wechatpush 拉取、服务预启用 |
| `release-clean.sh` | Release 保留策略：当月全留 + 最近 36 个月每月只留月末那次 |
| `test-config.sh` | 自检，不联网不编译 |
| `workflows/CUSTOM-AX6.yml` | AX6 专用编译入口（每月 10/20/月末 21:00，含月末 Gate） |
| `workflows/Custom-Clean.yml` | 每天 03:00 跑一次 Release 清理 |

## 用法（重新 fork 之后）

```bash
git clone https://github.com/<你>/OpenWRT-CI.git
cd OpenWRT-CI
# 把本目录放到仓库根：Custom/
bash Custom/bootstrap-fork.sh
bash Custom/test-config.sh
git add -A
git commit -m "custom: 只编 AX6 + 自选插件 + 每月 3 次"
git push
```

然后到 Actions 页面手动跑一次 `CUSTOM-AX6`（勾 `TEST` 可以先只出配置文件），确认无误后它就会按 cron 自动跑。

## 上游的两处「私有扩展入口」（我们正是用这两个，所以不用改核心）

1. `Scripts/Settings.sh` 第 35 行：如果存在 `Config/PRIVATE.txt`，会把它追加到 `.config` 末尾。
2. `Scripts/Packages.sh` 第 140 行：如果存在 `Scripts/PRIVATE.sh`，会 `source` 它。

## 改插件只需要两步

1. 编辑 `Custom/packages.seed`
2. 重跑 `bash Custom/bootstrap-fork.sh`（会把 seed 同步成 `Config/PRIVATE.txt`）

不需要动 workflow，也不需要动上游脚本。
