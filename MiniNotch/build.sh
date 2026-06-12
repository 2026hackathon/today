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

echo "==> [4/5] Ad-hoc 签名..."
# ad-hoc 签名：不需要 Apple Developer 账号
# 收到的人第一次打开需要：右键 → 打开 → 打开（绕过 Gatekeeper）
codesign --force --deep --sign - "${APP_BUNDLE}"

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
