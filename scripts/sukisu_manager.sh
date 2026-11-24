#!/usr/bin/env bash
set -euo pipefail

CHANNEL="${1:-release}"
KSU_DIR="${2:-KernelSU}"
# 管理器 APK 已迁到 cnb.cool/shirkneko/sukisu-result（zako 上的 Release 不再带 APK 资产）；
# 该端点需 Accept: application/json 才返回 JSON，字段与 Gitea 兼容
API="https://cnb.cool/shirkneko/sukisu-result/-/releases"
ACCEPT="Accept: application/json"

case "$CHANNEL" in
  最新*|latest*|HEAD*) ROLLING=true ;;
  *) ROLLING=false ;;
esac

RELEASE=""
if [ "$ROLLING" = false ]; then
  RELEASE=$(curl -fsSL --retry 3 --max-time 30 -H "$ACCEPT" "$API/latest")
  if [ -z "$RELEASE" ]; then
    echo "::notice::SukiSU-Nova 没有正式版 APK，改用 manager-ci"
    ROLLING=true
  fi
fi

if [ "$ROLLING" = true ]; then
  RELEASE=$(curl -fsSL --retry 3 --max-time 30 -H "$ACCEPT" "$API/tags/manager-ci")
fi

TAG=$(printf '%s' "$RELEASE" | jq -r '.tag_name')
ASSETS=$(printf '%s' "$RELEASE" | jq -r '
  [ .assets[]?
    | select(.name | test("release\\.apk$"; "i"))
    | select(.name | test("(?i)debug|spoofed") | not) ]
  | sort_by(if (.name | test("(?i)universal")) then 0
            elif (.name | test("(?i)arm64-v8a")) then 1 else 2 end)
  | .[] | [.name, .browser_download_url] | @tsv
')
if [ -z "$ASSETS" ]; then
  echo "::error::SukiSU-Nova $TAG 中没有可用的管理器 APK"
  exit 1
fi
IFS=$'\t' read -r APK_NAME _ <<< "$(printf '%s\n' "$ASSETS" | head -n 1)"
APK_NAME="${APK_NAME%$'\r'}"
if [[ "$APK_NAME" =~ _([0-9]+)(-(arm64-v8a|armeabi-v7a|armv7|riscv64|x86_64|x86|universal))?-release\.apk$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
else
  echo "::error::无法从 SukiSU-Nova APK 文件名解析版本: $APK_NAME"
  exit 1
fi

COMMIT=""
if [ "$ROLLING" = false ]; then
  COMMIT=$(git -C "$KSU_DIR" rev-parse --verify "${TAG}^{commit}")
else
  # The rolling release replaces APKs without moving its tag, so only the
  # current main history count can confirm that the APK was built from HEAD.
  COMMIT=$(git -C "$KSU_DIR" rev-parse origin/main)
fi
if [ -z "$COMMIT" ]; then
  echo "::error::无法在 SukiSU-Nova main 中找到与管理器 $VERSION 对齐的提交"
  exit 1
fi
COUNT=$(git -C "$KSU_DIR" rev-list --count "$COMMIT")
ACTUAL_VERSION=$((30000 + COUNT + 996))
if [ "$VERSION" -ne "$ACTUAL_VERSION" ]; then
  if [ "$ROLLING" = false ]; then
    echo "::error::SukiSU-Nova $TAG 的 APK 版本与标签提交不一致"
  else
    echo "::error::SukiSU-Nova manager-ci 版本 $VERSION 与 main HEAD 版本 $ACTUAL_VERSION 不一致，请等待上游 CI 完成"
  fi
  exit 1
fi

mkdir -p manager-artifacts
while IFS=$'\t' read -r NAME URL; do
  NAME="${NAME%$'\r'}"
  URL="${URL%$'\r'}"
  curl -fsSL --retry 3 --max-time 300 -o "manager-artifacts/$(basename "$NAME")" "$URL"
done <<< "$ASSETS"
echo "SukiSU-Nova $TAG: 管理器 $VERSION，内核版本来源提交 $COMMIT"
echo "MANAGER_VERSION=$VERSION" >> "$GITHUB_ENV"
{
  echo "managerVer=$VERSION"
  echo "ksuCommit=$COMMIT"
  if [ "$ROLLING" = false ]; then
    echo "channelTag=$TAG"
  fi
} >> "$GITHUB_OUTPUT"
