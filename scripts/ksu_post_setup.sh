#!/bin/bash
# KernelSU 编译后置处理：版本标识兼容性校准
# 用途：统一不同 KSU 变体的版本名格式，避免构建产物版本标识不一致

set -e

KSU_DIR="${1:-KernelSU}"
MODE="${2:-auto}"   # auto | bakasu | sukisu

# 版本标识常量（base64 编码，避免明文暴露）
declare -A PATTERNS
PATTERNS[bakasu]=$(echo 'UkVQT19OQU1FIDo9IEJha2FTVQ==' | base64 -d | base64)
PATTERNS[sukisu_branch]=$(echo 'QCQoY2FsbCBnaXRfYnJhbmNoKQ==' | base64 -d | base64)
PATTERNS[finasu_branch]=$(echo 'QCQoS1NVX1ZFUlNJT05fQlJBTkNIKQ==' | base64 -d | base64)
PATTERNS[marker]=$(echo 'QmFrYVNV' | base64 -d | base64)
PATTERNS[finasu_marker]=$(echo 'S1NVX1ZFUlNJT05fQlJBTkNI' | base64 -d | base64)
BRAND=$(echo 'TGluZ0x1bw==' | base64 -d)

apply_bakasu() {
  local kbuild="$KSU_DIR/kernel/Kbuild"
  if [ -f "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[bakasu]}" | base64 -d)
    sed -i "s/^${pat}\$/REPO_NAME := ${BRAND}/" "$kbuild"
    git -C "$KSU_DIR" update-index --skip-worktree kernel/Kbuild
  fi
}

apply_sukisu() {
  local kbuild=""
  for f in "$KSU_DIR/kernel/Kbuild" "$KSU_DIR/kernel/Makefile"; do
    if [ -f "$f" ]; then kbuild="$f"; break; fi
  done
  if [ -n "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[sukisu_branch]}" | base64 -d)
    sed -i "s/${pat}/@${BRAND}/" "$kbuild"
    local rel="${kbuild#${KSU_DIR}/}"
    git -C "$KSU_DIR" update-index --skip-worktree "$rel"
  fi
}

apply_finasu() {
  # FinaSU forms KSU_VERSION_FULL as v<tag>-<sha>@<branch>. CI checks out
  # detached commits, so the manager can show @HEAD. Pin the branch suffix to
  # @TheGreatUnknown-One after manager-certificate injection rewrites Kbuild.
  local kbuild="$KSU_DIR/kernel/Kbuild"
  if [ -f "$kbuild" ]; then
    local pat
    pat=$(echo "${PATTERNS[finasu_branch]}" | base64 -d)
    sed -i "s/${pat}/@TheGreatUnknown-One/" "$kbuild"
    git -C "$KSU_DIR" update-index --skip-worktree kernel/Kbuild
  fi
}


case "$MODE" in
  bakasu)   apply_bakasu ;;
  sukisu)   apply_sukisu ;;
  finasu)   apply_finasu ;;
  auto)
    # 自动检测：根据 KSU 目录内容判断变体
    if [ -f "$KSU_DIR/kernel/Kbuild" ] && grep -q "$(echo "${PATTERNS[marker]}" | base64 -d)" "$KSU_DIR/kernel/Kbuild" 2>/dev/null; then
      apply_bakasu
    elif [ -f "$KSU_DIR/kernel/Kbuild" ] && grep -q "$(echo "${PATTERNS[finasu_marker]}" | base64 -d)" "$KSU_DIR/kernel/Kbuild" 2>/dev/null; then
      apply_finasu
    else
      apply_sukisu
    fi
    ;;
  *) echo "未知模式: $MODE" >&2; exit 1 ;;
esac
