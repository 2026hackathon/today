#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# ============================================================
# 团队开发证书一键导入（FocusIsland Dev，自签名）
#
# 作用：run.sh / build.sh 检测到这张证书会用它签名，
# 签名身份稳定（identifier + 证书 leaf），macOS 日历/提醒
# 等 TCC 授权不会随重编译失效；团队互发的构建也保持同一身份。
#
# 每人每台机器只需运行一次。第 2 步系统可能弹密码确认框，
# 输入登录密码点「更新设置」即可。
# ============================================================

NAME="FocusIsland Dev"
P12="FocusIslandDev.p12"
CER="FocusIslandDev.cer"
P12_PASS="focusisland"  # 非机密：私钥本身就在仓库里，密码仅满足 p12 格式要求
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "${NAME}"; then
    echo "已存在可用的「${NAME}」签名身份，无需重复导入。"
    exit 0
fi

echo "==> [1/3] 导入证书和私钥到登录钥匙串..."
security import "$P12" -k "${KEYCHAIN}" -P "${P12_PASS}" -T /usr/bin/codesign

echo "==> [2/3] 信任证书用于代码签名（如弹窗请输入登录密码）..."
security add-trusted-cert -r trustRoot -p codeSign -k "${KEYCHAIN}" "${CER}"

echo "==> [3/3] 验证..."
security find-identity -v -p codesigning | grep "${NAME}"
echo ""
echo "完成！之后 run.sh / build.sh 会自动使用该证书签名。"
