#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# ============================================================
# MiniNotch 开发启动脚本
# debug 编译 → 组装 .app bundle → 重启应用。
#
# 为什么不能直接跑 .build/debug/MiniNotch：
# 裸二进制没有绑定 Info.plist（缺 NSCalendarsFullAccessUsageDescription），
# TCC 无法授予日历/提醒权限，EventKit 同步永远 accessDenied。
# 发布打包用 build.sh（universal + zip）。
# ============================================================

APP_NAME="MiniNotch"
BUILD_DIR=".build/debug"
APP_BUNDLE=".build/debug-app/${APP_NAME}.app"

echo "==> [1/3] Debug 编译..."
swift build

echo "==> [2/3] 组装 .app bundle..."
rm -rf "$(dirname "${APP_BUNDLE}")"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
# SwiftPM 资源 bundle（品牌 SVG 图标），存在则一并放入 Resources
if [ -d "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
# App 展示图标（Dock / Finder / 切换器）
[ -f AppIcon/AppIcon.icns ] && cp AppIcon/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# 优先用自签名证书（FocusIsland Dev）：签名身份稳定，TCC 日历授权
# 不随重编译失效；没有证书时退回 ad-hoc（每次编译都可能重新弹权限）
SIGN_ID="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "FocusIsland Dev"; then
    SIGN_ID="FocusIsland Dev"
fi
echo "==> 签名身份: ${SIGN_ID}"
codesign --force --deep --sign "${SIGN_ID}" "${APP_BUNDLE}"

echo "==> [3/3] 重启应用..."
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5
open "${APP_BUNDLE}"

echo ""
echo "已启动: ${APP_BUNDLE}"
if [ "${SIGN_ID}" = "-" ]; then
    echo "提示: 未找到「FocusIsland Dev」证书，已用 ad-hoc 签名 —— 重编译后系统可能重新弹日历权限弹窗。"
fi
