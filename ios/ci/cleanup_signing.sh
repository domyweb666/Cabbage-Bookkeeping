#!/usr/bin/env bash
# 刪掉暫時鑰匙圈、金鑰檔、描述檔與紀錄。不管前面成敗都要跑，所以每一步失敗都繼續。
set -uo pipefail

dir="${SIGN_DIR:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  echo "還沒建暫存資料夾，沒有東西要刪。"
  exit 0
fi
if [ -f "$dir/installed_profiles" ]; then
  while IFS= read -r path; do
    case "$path" in *.mobileprovision) rm -f "$path" ;; esac
  done < "$dir/installed_profiles"
fi
if [ -f "$dir/baicai-ci.keychain-db" ]; then
  security delete-keychain "$dir/baicai-ci.keychain-db" || true
fi
rm -rf "$dir"
if [ -e "$dir" ]; then
  echo "::error::暫存資料夾沒刪乾淨"
  exit 1
fi
echo "鑰匙圈與金鑰檔都刪了。"
