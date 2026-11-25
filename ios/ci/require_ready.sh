#!/usr/bin/env bash
# 出版前的門檻：只准在 main 跑，六個 secret 都要在。缺哪幾個一次列完。
# workflow 只傳 HAS_<名字>=true/false 進來，這支碰不到任何 secret 的值。
set -euo pipefail

if [ "${GITHUB_REF:-}" != "refs/heads/main" ]; then
  echo "::error::只准從 main 出版，這次選的是 ${GITHUB_REF:-（沒有分支資訊）}。改用：gh workflow run testflight.yml --ref main"
  exit 1
fi

missing=""
for name in APPLE_DIST_P12_BASE64 APPLE_DIST_P12_PASSWORD APPLE_TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8_BASE64; do
  flag="HAS_${name}"
  if [ "${!flag:-false}" != "true" ]; then missing="${missing:+${missing}、}${name}"; fi
done
if [ -n "$missing" ]; then
  echo "::error::缺 secret：${missing}。放法看 docs/上架指南.md 步驟 7。"
  exit 1
fi
echo "分支是 main，六個 secret 都在。"
