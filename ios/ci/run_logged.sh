#!/usr/bin/env bash
# 跑 xcodebuild。完整輸出只寫進暫存檔，畫面上只印結果與錯誤。
# 這個 repo 公開，Actions 紀錄誰都看得到，所以憑證名字、Team、金鑰 ID、信箱先塗掉再印。
# 用法：SIGN_DIR=... bash ios/ci/run_logged.sh <名稱> <指令> [參數...]
set -uo pipefail
# 這裡不設 umask，不然 app 裡的檔案權限會跟著變

: "${SIGN_DIR:?}"
label="${1:?要給名稱}"
shift
log="$SIGN_DIR/$label.log"

redact() {
  local args=(
    -e 's/((Apple|iPhone) (Distribution|Development|Developer)): [^"(]*(\([A-Z0-9]{10}\))?/\1: ***/g'
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]+/***/g'
  )
  local value
  # restore_asc_key.sh 驗過這三個值只有英數和連字號，放進 sed 不會被當成語法
  for value in "${APPLE_TEAM_ID:-}" "${ASC_KEY_ID:-}" "${ASC_ISSUER_ID:-}"; do
    if [[ "$value" =~ ^[A-Za-z0-9-]+$ ]]; then args+=(-e "s/$value/***/g"); fi
  done
  LC_ALL=C sed -E "${args[@]}"
}

"$@" > "$log" 2>&1
code=$?
if [ "$code" -eq 0 ]; then
  LC_ALL=C grep -E '\*\* |Upload succeeded|Uploaded ' "$log" | redact | tail -n 10
  exit 0
fi

echo "::group::$label 的錯誤"
LC_ALL=C grep -E 'error:|\*\* ' "$log" | awk '!seen[$0]++' | redact | tail -n 40
echo "::endgroup::"
echo "::group::$label 的最後 30 行"
tail -n 30 "$log" | redact
echo "::endgroup::"
echo "::error::$label 失敗（代碼 ${code}），原因看上面兩段。"
exit "$code"
