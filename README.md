# openwrt-ci-custom

`VIKINGYFY/OpenWRT-CI` 的 **AX6 定制层母版**。

这个仓库只放"定制层"，不放上游代码。作用是在你重新 fork 上游之后，
一条命令把全部定制装回去——因为重新 fork 会丢掉所有新增文件。

## 用法

```bash
git clone https://github.com/<你>/OpenWRT-CI.git
cd OpenWRT-CI
curl -fsSL https://raw.githubusercontent.com/wdss133/openwrt-ci-custom/main/install.sh | bash
git add -A && git commit -m "custom: 恢复 AX6 定制" && git push
```

`install.sh` 会把本仓库的 `Custom/` 拷到目标仓库，然后跑 `Custom/bootstrap-fork.sh`：
生成 `Config/AX6-WIFI-YES.txt`、`Config/PRIVATE.txt`、`Scripts/PRIVATE.sh`、
两个 workflow，重建 `README.md`，最后自检。

## 目录

| 文件 | 作用 |
|---|---|
| `install.sh` | 一键恢复入口（下载本仓库 → 拷 Custom → 跑 bootstrap） |
| `Custom/bootstrap-fork.sh` | 幂等定制：生成配置、装 workflow、重建 README、自检 |
| `Custom/packages.seed` | 插件清单（唯一需要日常改的文件） |
| `Custom/private.sh` | iStore 落位 / wechatpush / 服务预启用 |
| `Custom/gen-readme.sh` | 生成目标仓库的 README |
| `Custom/gen-release-body.sh` | 生成 Release 说明（两段式插件表） |
| `Custom/release-clean.sh` | Release 保留：当月全留 + 36 个月月末 |
| `Custom/test-config.sh` | 自检 |
| `Custom/workflows/` | `CUSTOM-AX6.yml` / `Custom-Clean.yml` 模板 |

## 注意

`Custom/` 是本仓库的唯一事实来源。改了定制脚本请**先改这里**，再同步到目标仓库；
否则下次重新 fork 时，目标仓库里的改动会被这里覆盖。
