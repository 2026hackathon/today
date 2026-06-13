#!/bin/bash
set -euo pipefail

# ============================================================
# MiniNotch 打包脚本
# 产出: MiniNotch.app (可直接双击运行) + MiniNotch.zip (发给别人)
# ============================================================

APP_NAME="MiniNotch"
BUILD_DIR=".build/apple/Products/Release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "==> [1/5] 清理旧产物..."
rm -rf dist
mkdir -p dist

echo "==> [2/5] Release 编译 (Universal Binary: arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

echo "==> [3/5] 组装 .app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# SwiftPM 资源 bundle 必须一起打进 Resources，否则发布版会丢资源：
# MiniNotch_MiniNotch.bundle = 品牌 SVG 图标（缺则退化成 SF Symbol）；
# SwiftGlow_SwiftGlow.bundle = 流光库的 Metal 资源（缺则 aiWorking 流光失效）。
for bundle in "${BUILD_DIR}"/*.bundle; do
    [ -e "${bundle}" ] && cp -R "${bundle}" "${APP_BUNDLE}/Contents/Resources/"
done

echo "==> [4/5] 签名..."
# 优先自签名证书（FocusIsland Dev）：本机 TCC 日历授权不随重编译失效；
# 无证书退回 ad-hoc。两种签名对接收方一样：第一次打开需右键 → 打开（绕过 Gatekeeper）
SIGN_ID="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "FocusIsland Dev"; then
    SIGN_ID="FocusIsland Dev"
fi
echo "    签名身份: ${SIGN_ID}"
codesign --force --deep --sign "${SIGN_ID}" "${APP_BUNDLE}"

echo "==> [5/5] 压缩为 zip..."
cd dist
zip -r -q "${APP_NAME}.zip" "${APP_NAME}.app"
cd ..

ZIP_SIZE=$(du -sh "dist/${APP_NAME}.zip" | awk '{print $1}')

echo ""
echo "============================================"
echo "  打包完成!"
echo "============================================"
echo ""
echo "  .app 位置: dist/${APP_NAME}.app"
echo "  .zip 位置: dist/${APP_NAME}.zip (${ZIP_SIZE})"
echo ""
echo "  本机测试: open dist/${APP_NAME}.app"
echo "  系统要求: macOS 14+ (Sonoma)"
echo "============================================"
