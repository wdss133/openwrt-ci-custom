#!/bin/bash
# ============================================================================
# Scripts/PRIVATE.sh —— 本分支私有扩展
# 由 Custom/bootstrap-fork.sh 安装到 Scripts/PRIVATE.sh，
# 被上游 Scripts/Packages.sh 末尾 `source` 调用。
# 执行位置：源码树根目录（./wrt/），此时 feeds 已 update/install 完毕。
#
# 只做三件事：
#   1) iStore 4 个子包落到 package/ 顶层（必须顶层，放 feeds/ 不会被注册）
#   2) 拉取 luci-app-wechatpush
#   3) 注入 uci-defaults，预启用 ddns-go / zerotier（它们默认 enabled=0）
# ============================================================================

echo " "
echo "========== PRIVATE.sh: 本分支私有扩展 =========="

# ---------------------------------------------------------------------------
# 1) iStore
#    关键点：必须放在 package/<pkg>/ 顶层真实目录。OpenWrt 的包扫描是
#    find -L package -name Makefile | grep 'call (BuildPackage|...)'
#    放 feeds/ 或嵌套目录都不会被注册。
#    另外去掉本 profile 里无法满足的依赖（libuci-lua 在 24.10+ 已移除、
#    tar / mount-utils 未随本 profile 选中），否则 kconfig 会整包丢弃。
# ---------------------------------------------------------------------------
ISTORE_TMP="$(mktemp -d)"
if git clone --depth=1 --single-branch https://github.com/linkease/istore.git "$ISTORE_TMP" >/dev/null 2>&1; then
	ISTORE_OK=1
	for PKG in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do
		if [ -d "$ISTORE_TMP/luci/$PKG" ]; then
			rm -rf "./package/$PKG"
			cp -a "$ISTORE_TMP/luci/$PKG" "./package/$PKG"
			find "./package/$PKG" -name Makefile -exec sed -i -E 's/[[:space:]]*\+(libuci-lua|tar|mount-utils)//g' {} + 2>/dev/null || true
			echo "istore: package/$PKG 已落位"
		else
			echo "istore: 缺少子包 luci/$PKG"
			ISTORE_OK=0
		fi
	done
	[ "$ISTORE_OK" -eq 1 ] && echo "istore: 4 个子包就绪"
else
	echo "istore: 仓库拉取失败，本次固件不含 iStore"
fi
rm -rf "$ISTORE_TMP"

# ---------------------------------------------------------------------------
# 2) luci-app-wechatpush
# ---------------------------------------------------------------------------
WXP_TMP="$(mktemp -d)"
if git clone --depth=1 --single-branch https://github.com/tty228/luci-app-wechatpush.git "$WXP_TMP" >/dev/null 2>&1; then
	rm -rf ./package/luci-app-wechatpush
	mkdir -p ./package/luci-app-wechatpush
	cp -a "$WXP_TMP/." ./package/luci-app-wechatpush/
	rm -rf ./package/luci-app-wechatpush/.git ./package/luci-app-wechatpush/.github
	echo "wechatpush: 已落位"
else
	echo "wechatpush: 仓库拉取失败，本次固件不含该插件"
fi
rm -rf "$WXP_TMP"

# ---------------------------------------------------------------------------
# 3) 首启预启用 ddns-go / zerotier
#    第三方包默认 enabled='0' 是设计如此，不注入的话"UI 能打开但核心不启动"。
#    幂等、缺文件不报错。
# ---------------------------------------------------------------------------
UCI_DIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DIR"
cat > "$UCI_DIR/98_custom_enable_services" <<'UCI_EOF'
#!/bin/sh
[ -x /sbin/uci ] || [ -x /bin/uci ] || exit 0

if [ -x /usr/bin/ddns-go ]; then
  grep -q '^ddns-go:' /etc/passwd 2>/dev/null || echo 'ddns-go:x:32769:32769:ddns-go:/var/run/ddns-go:/bin/false' >> /etc/passwd
  grep -q '^ddns-go:' /etc/group 2>/dev/null || echo 'ddns-go:x:32769:' >> /etc/group
fi
if [ -f /etc/config/ddns-go ]; then
  uci -q set ddns-go.config.enabled='1'
  uci -q commit ddns-go
fi
[ -x /etc/init.d/ddns-go ] && { /etc/init.d/ddns-go enable; /etc/init.d/ddns-go start; }

if [ -f /etc/config/zerotier ]; then
  uci -q set zerotier.global.enabled='1'
  uci -q delete zerotier.earth
  while uci -q delete zerotier.@network[0]; do :; done
  uci -q commit zerotier
fi
[ -x /etc/init.d/zerotier ] && { /etc/init.d/zerotier enable; /etc/init.d/zerotier start; }

exit 0
UCI_EOF
chmod +x "$UCI_DIR/98_custom_enable_services"
echo "uci-defaults: 已注入 98_custom_enable_services"

echo "========== PRIVATE.sh 完成 =========="
