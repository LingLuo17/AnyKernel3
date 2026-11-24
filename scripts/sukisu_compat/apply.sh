#!/usr/bin/env bash
# SukiSU-Nova 内核源码 API 兼容补丁（SukiSU-Nova builtin / main 分支均适用）
#
# 背景：
#   1) builtin 分支 kernel/hook/lsm_hook.c 仍以旧签名
#      security_add_hooks(hooks, count, "ksu") 注册 LSM 钩子，
#      6.8+ 内核要求 (hooks, count, const struct lsm_id *)，
#      android16-6.12 GKI 编译报 -Wincompatible-pointer-types（-Werror）；
#   2) builtin 在 app 启动路径对管理器/授权应用 disable_seccomp()，
#      管理器首页 "Seccomp 状态" 显示"未启用"；改为对齐 main 分支/BakaSU
#      的过滤模式（保留 seccomp 过滤器 + action cache 放行 reboot）。
#
# 已由上游修复、本仓库随之移除的适配（核对 builtin 5ef32ad / main 31255c4）：
#   - arch.h 缺失：builtin 已自带 kernel/arch.h（与本仓库旧副本逐字节一致）
#   - EVENT_SERVICES 缺失 / rules.c 重复声明：builtin 已随 UAPI 6 同步修复
#   - pkg_observer 的 track_throne(TRACK_THRONE_FORCE_SYNCHRONOUS)：已改回 false
#   - supercall.h 的 KSU_IOCTL_KPM 笔误 / KSU_IOCTL_MANAGER 缺声明：
#     上游已把 KPM / MANAGER 等并入统一的 KSU_IOCTL_EXTENSION，旧常量不复存在
#   - throne_tracker 的 crown_manager 裸 return / pkg 作用域：上游已修正
#   - netlink_kernel_cfg.cb_mutex（Linux 6.11 移除）：上游已改为构建期探测
#     目标 netlink.h 并定义 KSU_NETLINK_CFG_HAS_CB_MUTEX，super_access.c
#     以 #ifdef 守卫该成员（main: kernel/Kbuild / builtin: kernel/Makefile）
#
# 修复均以内容检测守卫，上游自行修复后自动跳过，重复执行幂等。
#
# 用法: apply.sh [KernelSU 目录]（调用方工作目录需为 $KERNEL_ROOT）

set -eo pipefail

KSU_DIR="${1:-KernelSU}"

fail() {
  echo "::error::$1"
  exit 1
}

[ -d "$KSU_DIR" ] || fail "未找到 KernelSU 目录: $KSU_DIR"

COMPAT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LSM_FILE="$KSU_DIR/kernel/hook/lsm_hook.c"
if [ -f "$LSM_FILE" ] && grep -q 'security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks), "ksu");' "$LSM_FILE"; then
  if grep -q 'ksu_lsm_id' "$LSM_FILE"; then
    echo "lsm_hook.c 已包含 lsm_id 兼容代码，跳过"
  else
    echo "应用 lsm_id 兼容补丁 (6.8+ security_add_hooks 新签名)..."
    patch -p1 --forward -d "$KSU_DIR" < "$COMPAT_DIR/sukisu-lsm-id-6.8.patch" \
      || fail "lsm_id 兼容补丁应用失败（SukiSU-Nova 上游代码可能已变化）"
    grep -q 'struct lsm_id ksu_lsm_id' "$LSM_FILE" \
      || fail "lsm_id 兼容补丁应用后校验失败"
    echo "lsm_hook.c: 6.8+ 已切换为 struct lsm_id 注册"
  fi
else
  echo "lsm_hook.c 不存在或无需 lsm_id 兼容补丁，跳过"
fi

# ---- Seccomp 过滤模式（builtin 分支）----
# 背景：builtin 分支在 app 启动路径（zygote setresuid 钩子）对管理器与授权
# 应用直接调用 disable_seccomp()，管理器进程自身的 seccomp 过滤器被清除，
# 管理器首页 "Seccomp 状态" 显示"未启用"。main 分支 / BakaSU 的对应实现是
# 保留过滤器（"过滤模式"），仅通过 seccomp action cache（GKI 5.10+ backport）
# 放行 reboot。
# 处理：改写 lsm_hook.c 的 6 处 disable_seccomp() 调用点为 cache-allow 形式，
# 分发 infra/seccomp_cache.c/h 并在 ksu.c（上游重构后为 ksu_main.c）聚合编译；>=5.10 保留过滤器，
# <5.10 维持 disable_seccomp() 原行为（action cache 不存在）。
# 守卫：仅命中 builtin 的 handle_zygote_setresuid 时执行，main 分支自动跳过；
# 上游自行修复后幂等跳过。
if [ -f "$LSM_FILE" ] && grep -q 'handle_zygote_setresuid' "$LSM_FILE"; then
  if grep -q 'ksu_seccomp_allow_cache' "$LSM_FILE"; then
    echo "lsm_hook.c 已包含 seccomp 过滤模式逻辑，跳过"
  else
    echo "应用 seccomp 过滤模式补丁 (对齐 main 分支/BakaSU：管理器与授权应用保留 seccomp 过滤器)..."
    [ -d "$KSU_DIR/kernel/infra" ] || fail "未找到 $KSU_DIR/kernel/infra 目录，SukiSU-Nova builtin 结构可能已变化"
    cp "$COMPAT_DIR/seccomp_cache.h" "$KSU_DIR/kernel/infra/seccomp_cache.h" \
      || fail "seccomp_cache.h 分发失败"
    cp "$COMPAT_DIR/seccomp_cache.c" "$KSU_DIR/kernel/infra/seccomp_cache.c" \
      || fail "seccomp_cache.c 分发失败"
    python3 "$COMPAT_DIR/seccomp_filter_mode.py" "$KSU_DIR" \
      || fail "seccomp 过滤模式补丁应用失败（SukiSU-Nova builtin 上游代码可能已变化）"
    grep -q 'ksu_seccomp_allow_cache' "$LSM_FILE" \
      || fail "seccomp 过滤模式补丁应用后校验失败 (lsm_hook.c)"
    # 聚合编译文件随上游重构更名（kernel/ksu.c -> kernel/ksu_main.c），按实际路径校验
    KSU_AGG=""
    for cand in kernel/ksu.c kernel/ksu_main.c; do
      if [ -f "$KSU_DIR/$cand" ]; then
        KSU_AGG="$KSU_DIR/$cand"
        break
      fi
    done
    if [ -z "$KSU_AGG" ] || ! grep -q '#include "infra/seccomp_cache.c"' "$KSU_AGG"; then
      fail "seccomp 过滤模式补丁应用后校验失败 (聚合编译文件 ksu.c/ksu_main.c)"
    fi
    grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)' "$KSU_DIR/kernel/infra/seccomp_cache.c" \
      || fail "seccomp_cache.c 版本守卫校验失败"
    echo "seccomp 过滤模式已启用：管理器首页 Seccomp 状态将显示\"过滤模式\""
  fi
else
  echo "lsm_hook.c 无 builtin setresuid 路径（main 分支已内置过滤模式），跳过 seccomp 过滤模式补丁"
fi

# ---- clang fall-through annotation ----
# builtin 的 policy/allowlist.c 使用注释形式 fall-through；bazel GKI
# 构建开启 -Werror,-Wimplicit-fallthrough 时会直接报错。改用内核
# fallthrough 宏（展开为 __attribute__((__fallthrough__))），上游修复后自动跳过。
if grep -rqF '/* fall through */' "$KSU_DIR/kernel" 2>/dev/null; then
  echo "修正 SukiSU-Nova 源码的注释式 fall-through（bazel -Werror 兼容）..."
  python3 - "$KSU_DIR" <<'PYEOF'
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "kernel"
for path in sorted(root.rglob("*.c")):
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    if "/* fall through */" not in text:
        continue
    path.write_text(
        text.replace("/* fall through */", "fallthrough;"),
        encoding="utf-8",
        errors="surrogateescape",
    )
    print(f"  {path}")
PYEOF
  if grep -rqF '/* fall through */' "$KSU_DIR/kernel" 2>/dev/null; then
    fail "fall-through 注解修正后仍有残留"
  fi
  echo "fall-through 注解修正完成"
else
  echo "SukiSU-Nova 源码无注释式 fall-through，跳过"
fi

# ---- 6.12+ LSM 静态调用槽位（builtin 分支）----
# 背景：6.12 的 LSM 框架把每个 hook 的回调预先编成 static call 表，
#   表宽是编译期算出的 MAX_LSM_COUNT（= 内建 LSM 数量）。
#   security_add_hooks() 里 lsm_active_cnt >= MAX_LSM_COUNT 直接
#   panic("Too many LSMs registered")。
#   GKI 启用 5 个基础 LSM（capabilities/selinux/safesetid/bpf_lsm/landlock），
#   BasebandGuard 也使用独立 lsm_id 注册，但不在 lsm_count.h 的计数宏中。
#   BBG + builtin SukiSU 需要额外两个槽位，不能再按没有 BBG 的 5+1 假设。
# 处理：给 MAX_LSM_COUNT 分别预留条件 KSU / BBG 槽位，static call 表随之加宽，
# 守卫：仅当内核启用 static call LSM 框架（security/security.c 含上述 panic）
#   且 KSU 驱动仍调用 security_add_hooks() 时执行；上游改用槽位改写后自动跳过。
LSM_ROOT="${KERNEL_ROOT:-.}"
LSM_COUNT_FILE="$LSM_ROOT/common/include/linux/lsm_count.h"
LSM_PANIC_GUARD="$LSM_ROOT/common/security/security.c"
if [ -f "$LSM_COUNT_FILE" ] && [ -f "$LSM_PANIC_GUARD" ] \
  && grep -qs 'Too many LSMs registered' "$LSM_PANIC_GUARD" \
  && grep -qs 'security_add_hooks(ksu_hooks' "$KSU_DIR/kernel/hook/lsm_hook.c"; then
  if grep -q 'KSU_ENABLED' "$LSM_COUNT_FILE" && grep -q 'BBG_ENABLED' "$LSM_COUNT_FILE"; then
    echo "lsm_count.h 已含外部 LSM 槽位，校验"
  else
    echo "为 KSU / BBG 预留 LSM static call 槽位..."
    python3 "$COMPAT_DIR/reserve_lsm_slot.py" "$LSM_COUNT_FILE" \
      || fail "lsm_count.h 增加 KSU 槽位失败"
  fi
  python3 "$COMPAT_DIR/reserve_lsm_slot.py" --verify "$LSM_COUNT_FILE" \
    || fail "lsm_count.h 中的 KSU 槽位未包含在 MAX_LSM_COUNT 内"
else
  echo "内核无 lsm_count.h 或 KSU 未用 security_add_hooks，跳过 LSM 槽位预留"
fi

echo "SukiSU-Nova API 兼容补丁处理完成"
