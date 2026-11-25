#!/usr/bin/env bash
# 選這台機器上最新的正式版 Xcode 26。beta、RC 和 27 以後的都不用，找不到就報錯。
# Apple 2027 年 4 月起要 iOS 27 SDK，到時候改 MAJOR，workflow 的機器一起換。
set -euo pipefail

MAJOR=26
APPS_DIR="${APPS_DIR:-/Applications}"

for app in $(ls -d "$APPS_DIR"/Xcode_"$MAJOR"*.app 2> /dev/null | sort -rV); do
  # 乾淨的檔名也可能是連到 beta 的捷徑，所以連過去的真正檔名一起看
  real="$(readlink -f "$app")"
  if printf '%s\n%s\n' "$(basename "$app")" "$(basename "$real")" | grep -Eqi 'beta|rc|candidate'; then
    continue
  fi
  info="$(DEVELOPER_DIR="$app/Contents/Developer" xcodebuild -version 2> /dev/null)" || continue
  version="$(awk '/^Xcode /{print $2}' <<< "$info")"
  build="$(awk '/^Build version /{print $3}' <<< "$info")"
  # 大版號要剛好；beta 的組建代號結尾是小寫字母（例如 17A5241e）
  if [ "${version%%.*}" != "$MAJOR" ]; then continue; fi
  case "$build" in *[[:lower:]]) continue ;; esac
  sudo xcode-select -s "$app/Contents/Developer"
  echo "用 Xcode ${version}（${build}）"
  exit 0
done

echo "::error::這台機器上找不到正式版 Xcode ${MAJOR}。現有的如下："
ls "$APPS_DIR" | grep -i xcode || true
exit 1
