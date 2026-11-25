#!/usr/bin/env bash
# 把 Apple Distribution 憑證（.p12）還原到暫時鑰匙圈。
# 環境變數：SIGN_DIR、APPLE_DIST_P12_BASE64、APPLE_DIST_P12_PASSWORD、APPLE_TEAM_ID
# 這支不會產生新憑證，也不會撤銷任何憑證。紀錄是公開的，憑證上的名字不印。
set -euo pipefail
umask 077

: "${SIGN_DIR:?}"
KEYCHAIN="$SIGN_DIR/baicai-ci.keychain-db"
P12="$SIGN_DIR/dist.p12"
trap 'rm -f "$P12"' EXIT

# 只准 base64 會出現的字
is_base64() {
  case "$1" in "" | *[!A-Za-z0-9+/=]*) return 1 ;; esac
}

# PowerShell 用管線放 secret 時，前面可能多一個看不見的 BOM，先拿掉
APPLE_DIST_P12_BASE64="$(printf '%s' "${APPLE_DIST_P12_BASE64:-}" | LC_ALL=C tr -d '\357\273\277')"
packed="$(printf '%s' "$APPLE_DIST_P12_BASE64" | tr -d '[:space:]')"
if ! is_base64 "$packed" || ! printf '%s' "$packed" | base64 --decode > "$P12" 2> /dev/null; then
  echo "::error::APPLE_DIST_P12_BASE64 不是有效的 base64。照 docs/上架指南.md 步驟 7 重放。"
  exit 1
fi
# .p12 是 DER，第一個 byte 一定是 30。放成 .cer 也會過這關，下面找簽章身分時會擋
if [ "$(head -c 1 "$P12" | od -An -tx1 | tr -d ' \n')" != "30" ]; then
  echo "::error::APPLE_DIST_P12_BASE64 還原出來不是 .p12（$(wc -c < "$P12" | tr -d ' ') bytes）。可能放成別的檔。"
  exit 1
fi

KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
echo "::add-mask::$KEYCHAIN_PASSWORD"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

# .p12 裡如果已經帶著 Apple 的中繼憑證，再匯一次會回 already exists，當成過（人蔘修煉 2026-11-15）
import_into_keychain() {
  local label="$1"
  shift
  echo "匯入：$label"
  if security import "$@" > /dev/null 2> "$SIGN_DIR/import.err"; then return 0; fi
  if grep -q "already exists" "$SIGN_DIR/import.err"; then
    echo "  已經在鑰匙圈裡，略過"
    return 0
  fi
  if grep -qiE "MAC verification failed|passphrase" "$SIGN_DIR/import.err"; then
    echo "::error::.p12 打不開：APPLE_DIST_P12_PASSWORD 不對，或 .p12 匯出時的加密方式 macOS 不吃（準則 2-23）。"
  else
    echo "::error::$label 匯入失敗：$(head -n 1 "$SIGN_DIR/import.err")"
  fi
  return 1
}

import_into_keychain "發佈憑證 .p12" "$P12" -P "${APPLE_DIST_P12_PASSWORD:-}" -A -t cert -f pkcs12 -k "$KEYCHAIN"
rm -f "$P12"
# 中繼憑證：簽章鏈要完整，codesign 才認得發佈憑證
for generation in G3 G4; do
  cer="$SIGN_DIR/wwdr-$generation.cer"
  curl -sSfL --retry 3 -o "$cer" "https://www.apple.com/certificateauthority/AppleWWDRCA$generation.cer"
  import_into_keychain "Apple 中繼憑證 $generation" "$cer" -k "$KEYCHAIN" -A
done
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db

# -v 只列還有效的。每行是「指紋 名字」，同一張列兩次只算一張
identities="$(security find-identity -v -p codesigning "$KEYCHAIN" |
  sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) "(Apple Distribution: .*)".*$/\1 \2/p' | sort -u)"
# 名字先請 GitHub 遮起來，之後 xcodebuild 印出來也看不到
count=0
hash=""
name=""
while read -r line_hash line_name; do
  if [ -z "$line_hash" ]; then continue; fi
  count=$((count + 1))
  hash="$line_hash"
  name="$line_name"
  holder="${line_name#Apple Distribution: }"
  echo "::add-mask::$line_name"
  echo "::add-mask::${holder% (*}"
done <<< "$identities"
if [ "$count" -ne 1 ]; then
  echo "::error::.p12 裡有效的 Apple Distribution 簽章身分有 ${count} 個，要剛好 1 個。0 個多半是過期、被撤銷、匯出時沒帶私鑰，或放成開發憑證。"
  exit 1
fi
if [[ "$name" != *"($APPLE_TEAM_ID)" ]]; then
  echo "::error::.p12 的 Team 跟 APPLE_TEAM_ID 不是同一個。"
  exit 1
fi

# 照指紋找出那一張，把序號留給 appstore_profile.mjs
security find-certificate -a -c "Apple Distribution" -p "$KEYCHAIN" > "$SIGN_DIR/all.pem"
awk -v prefix="$SIGN_DIR/cert-" '/BEGIN CERTIFICATE/{n++} n{print > (prefix n ".pem")}' "$SIGN_DIR/all.pem"
serial=""
for pem in "$SIGN_DIR"/cert-*.pem; do
  fingerprint="$(openssl x509 -in "$pem" -noout -fingerprint -sha1 | sed -e 's/.*=//' -e 's/://g')"
  if [ "$fingerprint" != "$hash" ]; then continue; fi
  serial="$(openssl x509 -in "$pem" -noout -serial | cut -d= -f2)"
  if ! openssl x509 -in "$pem" -noout -checkend 2592000 > /dev/null; then
    echo "::warning::這張發佈憑證 30 天內到期，記得換。"
  fi
done
if [ -z "$serial" ]; then
  echo "::error::鑰匙圈裡有簽章身分，但讀不到那張憑證的序號。"
  exit 1
fi
printf '%s\n' "$serial" > "$SIGN_DIR/cert_serial"
echo "發佈憑證可以用，Team 對得上。"
