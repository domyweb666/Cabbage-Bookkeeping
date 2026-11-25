#!/usr/bin/env bash
# 先驗 Team ID、Key ID、Issuer ID 的樣子，再把 API 金鑰還原成檔案並驗格式。只印形狀，不印內容。
# 用法：bash ios/ci/restore_asc_key.sh <輸出路徑>
# ASC_KEY_P8_BASE64 兩種放法都吃：base64 編過的一串，或 .p8 的原文（人蔘修煉兩種都放過）。
set -euo pipefail
umask 077

# 只准 base64 會出現的字
is_base64() {
  case "$1" in "" | *[!A-Za-z0-9+/=]*) return 1 ;; esac
}

OUT="${1:?要給輸出路徑}"
bad=""
if ! [[ "${APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]]; then bad="$bad APPLE_TEAM_ID（要 10 碼大寫英數）"; fi
if ! [[ "${ASC_KEY_ID:-}" =~ ^[A-Z0-9]{10}$ ]]; then bad="$bad ASC_KEY_ID（要 10 碼大寫英數）"; fi
if ! [[ "${ASC_ISSUER_ID:-}" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
  bad="$bad ASC_ISSUER_ID（要 36 碼、有四個連字號）"
fi
if [ -n "$bad" ]; then
  echo "::error::secret 的樣子不對：${bad}。多半是貼錯格，或前後多了空白、換行。"
  exit 1
fi

# PowerShell 用管線放 secret 時，前面可能多一個看不見的 BOM，先拿掉
ASC_KEY_P8_BASE64="$(printf '%s' "${ASC_KEY_P8_BASE64:-}" | LC_ALL=C tr -d '\357\273\277')"
if [[ "$ASC_KEY_P8_BASE64" == -----BEGIN* ]]; then
  form="原文"
  printf '%s\n' "$ASC_KEY_P8_BASE64" > "$OUT"
else
  form="base64"
  packed="$(printf '%s' "$ASC_KEY_P8_BASE64" | tr -d '[:space:]')"
  if ! is_base64 "$packed" || ! printf '%s' "$packed" | base64 --decode > "$OUT" 2> /dev/null; then
    rm -f "$OUT"
    echo "::error::ASC_KEY_P8_BASE64 不是有效的 base64。照 docs/上架指南.md 步驟 7 重放。"
    exit 1
  fi
fi

bytes="$(wc -c < "$OUT" | tr -d ' ')"
if ! LC_ALL=C head -c 27 "$OUT" | LC_ALL=C grep -q -e '-----BEGIN PRIVATE KEY-----'; then
  rm -f "$OUT"
  echo "::error::ASC_KEY_P8_BASE64 還原出來的開頭不是 BEGIN PRIVATE KEY（放法：${form}，${bytes} bytes）。可能放成別的檔。"
  exit 1
fi
if ! openssl pkey -in "$OUT" -noout 2> /dev/null; then
  rm -f "$OUT"
  echo "::error::ASC_KEY_P8_BASE64 有開頭，但金鑰內容讀不了（放法：${form}，${bytes} bytes，正常約 257）。可能缺了幾行，或換行不見了。"
  exit 1
fi
echo "API 金鑰格式正確（放法：${form}，${bytes} bytes）"
