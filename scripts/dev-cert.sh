#!/bin/bash
# One-time setup: create a self-signed CODE-SIGNING certificate named
# "TinyWindow Dev" in the login keychain. Signing with it gives the app a
# STABLE designated requirement, so the Accessibility grant survives rebuilds
# (ad-hoc signatures get a new cdhash every build and silently lose the grant).
#
# GUI alternative (often smoother, ~1 minute):
#   Keychain Access → 证书助理 → 创建证书…
#   名称 "TinyWindow Dev" · 身份类型 "自签名根证书" · 证书类型 "代码签名"
#   如 codesign 报错，再双击该证书 → 信任 → 代码签名 → 始终信任
set -euo pipefail

NAME="${1:-TinyWindow Dev}"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

PASS="$(uuidgen)"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/dev.p12" -passout "pass:$PASS" -name "$NAME"

# May prompt once; -T pre-authorizes codesign to use the key without asking.
security import "$TMP/dev.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASS" -T /usr/bin/codesign

# Trust the cert for code signing. Newer macOS restricts scripted trust changes;
# if this fails, do the GUI trust step from the header comment.
if security add-trusted-cert -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem" 2>/dev/null; then
  echo "Trust set."
else
  echo "⚠ 自动设置信任失败（新版 macOS 限制脚本改信任）。"
  echo "  请打开「钥匙串访问」→ 双击 '$NAME' 证书 → 信任 → 代码签名 → 始终信任"
fi

echo "Done. 验证：security find-identity -v -p codesigning"
