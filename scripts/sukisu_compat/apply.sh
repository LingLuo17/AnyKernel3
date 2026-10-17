#!/usr/bin/env bash
# SukiSU 内核源码 API 兼容补丁（SukiSU-Ultra builtin / main 分支均适用）
#
# 背景：
#   1) builtin 分支 kernel/hook/lsm_hook.c 仍以旧签名
#      security_add_hooks(hooks, count, "ksu") 注册 LSM 钩子，
#      6.8+ 内核要求 (hooks, count, const struct lsm_id *)，
#      android16-6.12 GKI 编译报 -Wincompatible-pointer-types（-Werror）；
#   2) kernel/kpm/super_access.c 引用 netlink_kernel_cfg.cb_mutex，
#      该成员在 Linux 6.11 被上游移除，KPM 开启时 6.11+ 内核编译失败。
#   3) builtin 2026-10-05 同步官方 KernelSU 后 kernel_includes.h
#      引用 arch.h，但该文件只在 main 分支存在，builtin 漏带，
#      所有平台编译报 fatal error: 'arch.h' file not found；
#   4) 同步同时引入两处编译错误：supercall/dispatch.c 引用未定义的
#      EVENT_SERVICES（uapi 头缺常量），selinux/rules.c 在 5.10+ 分支
#      重复声明 pol/old_pol。
#   5) builtin 在 app 启动路径对管理器/授权应用 disable_seccomp()，
#      管理器首页 "Seccomp 状态" 显示"未启用"；改为对齐 main 分支/BakaSU
#      的过滤模式（保留 seccomp 过滤器 + action cache 放行 reboot）。
#
# 修复均以内容检测守卫，上游自行修复后自动跳过，重复执行幂等。
#
# 用法: apply.sh [KernelSU 目录]（调用方工作目录需为 $KERNEL_ROOT）

set -eo pipefail

KSU_DIR="${1:-KernelSU}"

fail() {
  if [ "$SKIP_INCOMPATIBLE" = "true" ]; then
    echo "::warning title=SukiSU 兼容补丁已跳过::$1"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "" >> "$GITHUB_STEP_SUMMARY"
      echo "> ⏭️ **SukiSU API 兼容补丁** 已自动跳过：$1（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
  fi
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
      || fail "lsm_id 兼容补丁应用失败（SukiSU 上游代码可能已变化）"
    grep -q 'struct lsm_id ksu_lsm_id' "$LSM_FILE" \
      || fail "lsm_id 兼容补丁应用后校验失败"
    echo "lsm_hook.c: 6.8+ 已切换为 struct lsm_id 注册"
  fi
else
  echo "lsm_hook.c 不存在或无需 lsm_id 兼容补丁，跳过"
fi

SUPER_FILE="$KSU_DIR/kernel/kpm/super_access.c"
if [ -f "$SUPER_FILE" ] && grep -q 'DEFINE_MEMBER(netlink_kernel_cfg, cb_mutex)' "$SUPER_FILE"; then
  if grep -q 'KERNEL_VERSION(6, 11, 0)' "$SUPER_FILE"; then
    echo "super_access.c 已包含 cb_mutex 版本守卫，跳过"
  else
    echo "应用 cb_mutex 兼容补丁 (6.11+ 移除 netlink_kernel_cfg.cb_mutex)..."
    patch -p1 --forward -d "$KSU_DIR" < "$COMPAT_DIR/sukisu-cb-mutex-6.11.patch" \
      || fail "cb_mutex 兼容补丁应用失败（SukiSU 上游代码可能已变化）"
    grep -q 'KERNEL_VERSION(6, 11, 0)' "$SUPER_FILE" \
      || fail "cb_mutex 兼容补丁应用后校验失败"
    echo "super_access.c: 6.11+ 已跳过 cb_mutex 成员"
  fi
else
  echo "super_access.c 不存在或无需 cb_mutex 兼容补丁，跳过"
fi

# builtin 分支 2026-10-05 同步官方 KernelSU（70fa0e092）后，
# kernel/kernel_includes.h 引用 #include "arch.h"，但 arch.h 只存在于
# main 分支（kernel/include/arch.h），builtin 漏带导致全部平台编译失败:
#   fatal error: 'arch.h' file not found
# 从本仓库分发 main 分支的 arch.h，检测到缺失时补齐；
# 上游修复（builtin 自带 arch.h）后自动跳过，幂等。
ARCH_REF="$KSU_DIR/kernel/include/arch.h"
if [ -f "$KSU_DIR/kernel/kernel_includes.h" ] && grep -q '#include "arch.h"' "$KSU_DIR/kernel/kernel_includes.h"; then
  if [ -f "$ARCH_REF" ]; then
    echo "arch.h 已存在，跳过补齐"
  else
    echo "补齐缺失的 arch.h（builtin 同步官方 KernelSU 时遗漏）..."
    cp "$COMPAT_DIR/arch.h" "$ARCH_REF" \
      || fail "arch.h 补齐失败"
    grep -q '__KSU_H_ARCH' "$ARCH_REF" \
      || fail "arch.h 补齐后校验失败"
    echo "arch.h: 已补齐 (提供 PT_REGS_* / __ksyscall 所需的架构寄存器宏)"
  fi
else
  echo "kernel_includes.h 不存在或未引用 arch.h，跳过补齐"
fi

# builtin 分支 2026-10-05 同步官方 KernelSU 后遗留的两处编译错误
# （全平台构建在 ksu.c 聚合编译阶段命中）：
#   1) supercall/dispatch.c 引用 EVENT_SERVICES，
#      但 builtin 的 uapi 头只定义了 EVENT 1/2/3，缺 EVENT_SERVICES = 4；
#   2) selinux/rules.c 在 #if >= 5.10 块内重复声明 pol/old_pol
#      （函数开头已声明），C89 风格重定义直接编译失败。
# 以内容检测守卫：主头已含 EVENT_SERVICES 或重复声明已消失时自动跳过，幂等。
DISP_FILE="$KSU_DIR/kernel/supercall/dispatch.c"
RULES_FILE="$KSU_DIR/kernel/selinux/rules.c"
if { [ -f "$DISP_FILE" ] && grep -q 'EVENT_SERVICES' "$DISP_FILE" && \
     ! grep -q 'EVENT_SERVICES' "$KSU_DIR/kernel/include/uapi/supercall.h"; } || \
   { [ -f "$RULES_FILE" ] && grep -q 'struct selinux_policy \*pol, \*old_pol = selinux_state.policy;' "$RULES_FILE"; }; then
  echo "应用 builtin 同步遗留问题修复 (EVENT_SERVICES + rules.c 重复声明)..."
  patch -p1 --forward -d "$KSU_DIR" < "$COMPAT_DIR/builtin-sync-fixes.patch" \
    || fail "builtin 同步遗留修复应用失败（SukiSU 上游代码可能已变化）"
  grep -q 'EVENT_SERVICES, 4' "$KSU_DIR/kernel/include/uapi/supercall.h" \
    || fail "EVENT_SERVICES 补齐后校验失败"
  ! grep -q 'struct selinux_policy \*pol, \*old_pol = selinux_state.policy;' "$RULES_FILE" \
    || fail "rules.c 重复声明修复后校验失败"
  echo "EVENT_SERVICES 已补齐; rules.c 重复声明已移除"
else
  echo "builtin 同步遗留问题不存在或已修复，跳过"
fi

# builtin 分支 2026-10-14 合入 PR #3871（pkg_observer 延迟 track_throne 到
# task_work，c8959206）时，pkg_observer.c 两处以
# track_throne(TRACK_THRONE_FORCE_SYNCHRONOUS) 调用，但 builtin 的
# track_throne() 仍为 bool prune_only 形参，TRACK_THRONE_FORCE_SYNCHRONOUS
# 未在任何头文件定义（BakaSU 的 flags 版 throne_tracker API 未随补丁同步），
# ksu.c 聚合编译报：
#   error: use of undeclared identifier 'TRACK_THRONE_FORCE_SYNCHRONOUS'
# main 分支同函数即 track_throne(false)（false=全量扫描，非 prune-only），
# builtin 的 fsnotify 路径同样需要全量扫描，依此替换；上游修复后按内容
# 检测自动跳过，幂等。
PKG_OBS_FILE="$KSU_DIR/kernel/manager/pkg_observer.c"
if [ -f "$PKG_OBS_FILE" ] && grep -q 'track_throne(TRACK_THRONE_FORCE_SYNCHRONOUS)' "$PKG_OBS_FILE"; then
  echo "应用 pkg_observer 修复 (builtin PR #3871 引用未定义的 TRACK_THRONE_FORCE_SYNCHRONOUS)..."
  sed -i 's/track_throne(TRACK_THRONE_FORCE_SYNCHRONOUS)/track_throne(false)/g' "$PKG_OBS_FILE" \
    || fail "pkg_observer.c track_throne 修复失败"
  ! grep -q 'TRACK_THRONE_FORCE_SYNCHRONOUS' "$PKG_OBS_FILE" \
    || fail "pkg_observer.c TRACK_THRONE_FORCE_SYNCHRONOUS 修复后校验失败"
  grep -q 'track_throne(false)' "$PKG_OBS_FILE" \
    || fail "pkg_observer.c track_throne(false) 修复后校验失败"
  echo "pkg_observer.c: 未定义的 TRACK_THRONE_FORCE_SYNCHRONOUS 已替换为 track_throne(false)"
else
  echo "pkg_observer.c 未引用 TRACK_THRONE_FORCE_SYNCHRONOUS，跳过"
fi

# ---- Seccomp 过滤模式（builtin 分支）----
# 背景：builtin 分支在 app 启动路径（zygote setresuid 钩子）对管理器与授权
# 应用直接调用 disable_seccomp()，管理器进程自身的 seccomp 过滤器被清除，
# 管理器首页 "Seccomp 状态" 显示"未启用"。main 分支 / BakaSU 的对应实现是
# 保留过滤器（"过滤模式"），仅通过 seccomp action cache（GKI 5.10+ backport）
# 放行 reboot。
# 处理：改写 lsm_hook.c 的 6 处 disable_seccomp() 调用点为 cache-allow 形式，
# 分发 infra/seccomp_cache.c/h 并在 ksu.c 聚合编译；>=5.10 保留过滤器，
# <5.10 维持 disable_seccomp() 原行为（action cache 不存在）。
# 守卫：仅命中 builtin 的 handle_zygote_setresuid 时执行，main 分支自动跳过；
# 上游自行修复后幂等跳过。
if [ -f "$LSM_FILE" ] && grep -q 'handle_zygote_setresuid' "$LSM_FILE"; then
  if grep -q 'ksu_seccomp_allow_cache' "$LSM_FILE"; then
    echo "lsm_hook.c 已包含 seccomp 过滤模式逻辑，跳过"
  else
    echo "应用 seccomp 过滤模式补丁 (对齐 main 分支/BakaSU：管理器与授权应用保留 seccomp 过滤器)..."
    [ -d "$KSU_DIR/kernel/infra" ] || fail "未找到 $KSU_DIR/kernel/infra 目录，SukiSU builtin 结构可能已变化"
    cp "$COMPAT_DIR/seccomp_cache.h" "$KSU_DIR/kernel/infra/seccomp_cache.h" \
      || fail "seccomp_cache.h 分发失败"
    cp "$COMPAT_DIR/seccomp_cache.c" "$KSU_DIR/kernel/infra/seccomp_cache.c" \
      || fail "seccomp_cache.c 分发失败"
    python3 "$COMPAT_DIR/seccomp_filter_mode.py" "$KSU_DIR" \
      || fail "seccomp 过滤模式补丁应用失败（SukiSU builtin 上游代码可能已变化）"
    grep -q 'ksu_seccomp_allow_cache' "$LSM_FILE" \
      || fail "seccomp 过滤模式补丁应用后校验失败 (lsm_hook.c)"
    grep -q '#include "infra/seccomp_cache.c"' "$KSU_DIR/kernel/ksu.c" \
      || fail "seccomp 过滤模式补丁应用后校验失败 (ksu.c)"
    grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)' "$KSU_DIR/kernel/infra/seccomp_cache.c" \
      || fail "seccomp_cache.c 版本守卫校验失败"
    echo "seccomp 过滤模式已启用：管理器首页 Seccomp 状态将显示\"过滤模式\""
  fi
else
  echo "lsm_hook.c 无 builtin setresuid 路径（main 分支已内置过滤模式），跳过 seccomp 过滤模式补丁"
fi

# builtin 分支 2026-10-15 合入 PR #987（动态多管理器签名授权，a2339013）时，
# supercall.h 的 UAPI 常量声明有两处笔误（main 分支同名代码是正确写法）：
#   1) 新 ioctl 常量错用已存在的 KSU_IOCTL_KPM（_IOC('K',200)），
#      正确名称是 KSU_IOCTL_MANAGER（dispatch.c 的处理表引用它），同名重复
#      声明在匿名 enum 里直接报 "redefinition of enumerator 'KSU_IOCTL_KPM'"；
#   2) _IOWR 第三个参数少了 struct 关键字——_IOWR 展开为 sizeof(ksu_manager_cmd)，
#      裸 tag 名不是类型，报 "use of undeclared identifier 'ksu_manager_cmd'"。
# 全平台构建在 ksu.c 聚合编译阶段命中。依 main 分支 uapi/supercall.h 的
# KSU_IOCTL_MANAGER = _IOWR('K', 106, struct ksu_manager_cmd) 修正；
# 上游自行修复后按内容检测自动跳过，幂等。
UAPI_FILE="$KSU_DIR/kernel/include/uapi/supercall.h"
if [ -f "$UAPI_FILE" ] && grep -q "DECLARE(__u32, KSU_IOCTL_KPM, _IOWR" "$UAPI_FILE" \
  && ! grep -q 'KSU_IOCTL_MANAGER,' "$UAPI_FILE"; then
  echo "应用 supercall.h 管理器 ioctl 修复 (PR #987 常量名笔误 + 缺 struct 关键字)..."
  sed -i "s|^DECLARE(__u32, KSU_IOCTL_KPM, _IOWR('K', 106, .*\$|DECLARE(__u32, KSU_IOCTL_MANAGER, _IOWR('K', 106, struct ksu_manager_cmd));|" "$UAPI_FILE" \
    || fail "supercall.h KSU_IOCTL_MANAGER 修复失败"
  grep -q "DECLARE(__u32, KSU_IOCTL_MANAGER, _IOWR('K', 106, struct ksu_manager_cmd));" "$UAPI_FILE" \
    || fail "supercall.h KSU_IOCTL_MANAGER 修复后校验失败"
  [ "$(grep -c 'DECLARE(__u32, KSU_IOCTL_KPM,' "$UAPI_FILE")" -eq 1 ] \
    || fail "supercall.h KSU_IOCTL_KPM 重复声明未消除"
  echo "supercall.h: KSU_IOCTL_MANAGER 已按 main 分支写法补齐，KSU_IOCTL_KPM 重复声明已消除"
elif [ -f "$UAPI_FILE" ] && ! grep -q 'KSU_IOCTL_MANAGER' "$UAPI_FILE" \
  && grep -q 'DECLARE(__u32, KSU_IOCTL_KPM, _IOC(_IOC_READ | _IOC_WRITE, .K., 200, 0))' "$UAPI_FILE" \
  && [ -f "$KSU_DIR/kernel/supercall/dispatch.c" ] \
  && grep -q '\.cmd = KSU_IOCTL_MANAGER,' "$KSU_DIR/kernel/supercall/dispatch.c"; then
  # 上游 c95d6e2c/0af2cf9 自行修正了 KSU_IOCTL_KPM 笔误（恢复 200 号），却没有补回
  # KSU_IOCTL_MANAGER 的声明——dispatch.c 处理表仍引用它，全部平台报
  # "use of undeclared identifier 'KSU_IOCTL_MANAGER'"。按 main 分支写法
  # （KSU_IOCTL_MANAGER = _IOWR('K', 106, struct ksu_manager_cmd)，struct 由
  # manager.h 提供，supercall.h 已 include）在 KSU_IOCTL_KPM 声明前补上，幂等；
  # 上游自行补齐后按内容检测自动跳过。
  echo "应用 supercall.h 管理器 ioctl 补齐 (上游自修笔误后缺 KSU_IOCTL_MANAGER 声明)..."
  python3 - "$UAPI_FILE" <<'PYEOF'
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8", errors="surrogateescape").read()
kpm = "DECLARE(__u32, KSU_IOCTL_KPM, _IOC(_IOC_READ | _IOC_WRITE, 'K', 200, 0));"
mgr = "DECLARE(__u32, KSU_IOCTL_MANAGER, _IOWR('K', 106, struct ksu_manager_cmd));"
if s.count(kpm) != 1:
    print("::error::supercall.h KSU_IOCTL_KPM 声明形态不是预期（count=%d）" % s.count(kpm))
    sys.exit(1)
open(path, "w", encoding="utf-8", errors="surrogateescape").write(
    s.replace(kpm, mgr + "\n" + kpm, 1))
print("supercall.h: KSU_IOCTL_MANAGER 声明已插入（106 号，struct ksu_manager_cmd）")
PYEOF
  grep -q "DECLARE(__u32, KSU_IOCTL_MANAGER, _IOWR('K', 106, struct ksu_manager_cmd));" "$UAPI_FILE" \
    || fail "supercall.h KSU_IOCTL_MANAGER 补齐后校验失败"
  [ "$(grep -c 'DECLARE(__u32, KSU_IOCTL_KPM,' "$UAPI_FILE")" -eq 1 ] \
    || fail "supercall.h KSU_IOCTL_KPM 声明数量异常"
  echo "supercall.h: KSU_IOCTL_MANAGER 已按 main 分支写法补齐（106 号，struct ksu_manager_cmd）"
else
  echo "supercall.h 无 PR #987 的 KSU_IOCTL_KPM 笔误，跳过"
fi

# builtin 分支 PR #987 同时引入 throne_tracker.c 的 crown_manager() 两处问题：
#   1) a2339013 形态：get_pkg_from_apk_path 解析失败分支写了裸 return;（非 void
#      函数），clang -Wreturn-type 报错；且未定义返回值时调用方按未定值处理，
#      若碰巧 >0 会让扫描提前终止。按文档契约（返回 0 = 本候选无效、未观察到
#      内置候选、继续扫描；-1 需 state->seen 已置位，此处不成立）补为 return 0;。
#      c95d6e2c 已自行修复此分支（改为 "apk dir path" + return 0;），自动跳过。
#   2) c95d6e2c 形态：签名改为 (apk, apk_dir, ..., sig_fallback) 后，pkg 数组
#      被移进 if (sig_fallback) 块内声明，而函数尾部的动态管理器扫描循环
#      (strncmp(np->package, pkg, ...)) 仍在块外引用——所有平台报
#      "use of undeclared identifier 'pkg'"。把声明上提到函数声明块并初始化为
#      KSU_PACKAGE_NAME（sig_fallback=false 时跳过内置包名条目，与 fallback
#      分支"跳过已处理候选"的语义一致；fallback 路径 get_pkg_* 会覆盖它）。
# 上游修复后按内容检测自动跳过，幂等。
THRONE_FILE="$KSU_DIR/kernel/manager/throne_tracker.c"
if [ -f "$THRONE_FILE" ] && grep -q 'static int crown_manager' "$THRONE_FILE" \
  && grep -A1 'Failed to get package name from apk path' "$THRONE_FILE" | grep -q '^[[:space:]]*return;[[:space:]]*$'; then
  echo "应用 throne_tracker.c crown_manager 返回值修复 (PR #987 裸 return;)..."
  sed -i '/Failed to get package name from apk path/{n;s/^\([[:space:]]*\)return;[[:space:]]*$/\1return 0;/}' "$THRONE_FILE" \
    || fail "throne_tracker.c crown_manager 返回值修复失败"
  grep -A1 'Failed to get package name from apk path' "$THRONE_FILE" | grep -q 'return 0;' \
    || fail "throne_tracker.c crown_manager 返回值修复后校验失败"
  ! grep -A1 'Failed to get package name from apk path' "$THRONE_FILE" | grep -q '^[[:space:]]*return;[[:space:]]*$' \
    || fail "throne_tracker.c 裸 return 未消除"
  echo "throne_tracker.c: crown_manager 解析失败分支已补 return 0;"
else
  echo "throne_tracker.c 无 crown_manager 裸 return，跳过"
fi

if [ -f "$THRONE_FILE" ] && grep -q '^        char pkg\[KSU_MAX_PACKAGE_NAME\];$' "$THRONE_FILE" \
  && grep -q 'strncmp(np->package, pkg, KSU_MAX_PACKAGE_NAME)' "$THRONE_FILE" \
  && ! grep -q 'char pkg\[KSU_MAX_PACKAGE_NAME\] = ' "$THRONE_FILE"; then
  echo "应用 throne_tracker.c crown_manager pkg 作用域修复 (c95d6e2c 块外引用)..."
  sed -i '/^        char pkg\[KSU_MAX_PACKAGE_NAME\];$/d' "$THRONE_FILE" \
    || fail "throne_tracker.c pkg 内层声明删除失败"
  sed -i 's/^    bool builtin_crowned_this_call = false;$/    bool builtin_crowned_this_call = false;\n    char pkg[KSU_MAX_PACKAGE_NAME] = KSU_PACKAGE_NAME;/' "$THRONE_FILE" \
    || fail "throne_tracker.c pkg 声明上提失败"
  grep -q 'char pkg\[KSU_MAX_PACKAGE_NAME\] = KSU_PACKAGE_NAME;' "$THRONE_FILE" \
    || fail "throne_tracker.c pkg 声明上提后校验失败"
  ! grep -q '^        char pkg\[KSU_MAX_PACKAGE_NAME\];$' "$THRONE_FILE" \
    || fail "throne_tracker.c pkg 内层声明未消除"
  echo "throne_tracker.c: pkg 已上提到函数作用域并以 KSU_PACKAGE_NAME 初始化"
else
  echo "throne_tracker.c 无 crown_manager pkg 作用域问题，跳过"
fi

echo "SukiSU API 兼容补丁处理完成"
