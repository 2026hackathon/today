#!/bin/bash
set -euo pipefail

# ============================================================
# Next 打包脚本（内部代号 MiniNotch）
# 产出: Next.app (可直接双击运行) + Next.zip (发给别人)
# 说明: 可执行文件名沿用 SwiftPM target「MiniNotch」，对用户不可见；
#       产品名 / 包名 / 显示名统一为「Next」。
# ============================================================

APP_NAME="Next"              # 产品名：.app / .zip / 显示名
BIN_NAME="MiniNotch"         # 可执行文件名（= SwiftPM target，勿改）
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

# 可执行文件名保持 BIN_NAME（须与 Info.plist 的 CFBundleExecutable 一致）
cp "${BUILD_DIR}/${BIN_NAME}" "${APP_BUNDLE}/Contents/MacOS/${BIN_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
# App 展示图标（Dock / Finder / 切换器）
[ -f AppIcon/AppIcon.icns ] && cp AppIcon/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# SwiftPM 资源 bundle 必须一起打进 Resources，否则发布版会丢资源：
# MiniNotch_MiniNotch.bundle = 品牌 SVG 图标（缺则退化成 SF Symbol）。
# 注：glow/流光已改为纯 SwiftUI 自绘，不再依赖第三方 Metal 资源 bundle。
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
