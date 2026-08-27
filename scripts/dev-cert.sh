#!/bin/bash
# One-time setup: create a self-signed CODE-SIGNING certificate named
# "TinyWindow Dev" in the login keychain. Signing with it gives the app a
# STABLE designated requirement, so the Accessibility grant survives rebuilds
# (ad-hoc signatures get a new cdhash every build and silently lose the grant).
#
# Safe to re-run: it picks up wherever a previous run stopped and ends with a
# real signing test, so "✔" means codesign actually works.
#
# Notes that shaped this script:
# - No .p12: OpenSSL 3 emits PKCS#12 with modern algorithms that macOS's
#   `security import` cannot parse ("MAC verification failed"). Importing the
#   key and cert as separate PEMs sidesteps the whole problem.
# - macOS 26 hides Keychain Access at
#   /System/Library/CoreServices/Applications/ and often refuses scripted
#   trust changes — the manual trust fallback below is precise for it.
set -euo pipefail

NAME="${1:-TinyWindow Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sign_test() {
  cp -f /bin/ls "$TMP/signtest"
  codesign --force --sign "$NAME" "$TMP/signtest" 2>"$TMP/sign.err"
}

manual_trust_help() {
  echo ""
  echo "还差最后一步——手动设置信任（约 20 秒）："
  echo "  1. 打开钥匙串访问（macOS 26 里被隐藏了，不是「密码」App）："
  echo "       open \"/System/Library/CoreServices/Applications/Keychain Access.app\""
  echo "  2. 左侧选「登录」，上方分类选「证书」，双击「$NAME」"
  echo "  3. 展开「信任」→「代码签名」选「始终信任」→ 关闭小窗 → 输入登录密码确认"
  echo "  4. 重新运行本脚本验证：bash scripts/dev-cert.sh"
}

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "证书「$NAME」已在钥匙串中，直接验证能否签名…"
  echo "（如果弹出「codesign 想要使用密钥」，请点「始终允许」）"
  if sign_test; then
    echo "✔ 一切就绪！运行 make run 重新构建即可。"
    exit 0
  fi
  echo "✖ 证书存在但还不能签名：$(cat "$TMP/sign.err" | head -2)"
  manual_trust_help
  exit 1
fi

echo "→ 生成自签代码签名证书…"
cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_code
prompt = no
[dn]
CN = $NAME
[v3_code]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
EOF
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf" 2>/dev/null

echo "→ 导入登录钥匙串（可能弹出系统确认框）…"
security import "$TMP/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
security import "$TMP/cert.pem" -k "$KEYCHAIN"

echo "→ 尝试设置代码签名信任（新版 macOS 可能拒绝命令行方式，属正常）…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null \
  || echo "  （命令行设置信任被系统拒绝，稍后按提示手动设置）"

echo "→ 实际验签测试…（如弹出「codesign 想要使用密钥」，请点「始终允许」）"
if sign_test; then
  echo "✔ 完成！「$NAME」可用于签名。运行 make run 重新构建即可。"
  exit 0
fi

echo "✖ 证书已导入，但签名验证未通过：$(cat "$TMP/sign.err" | head -2)"
manual_trust_help
exit 1
