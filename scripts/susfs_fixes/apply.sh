#!/usr/bin/env bash
# 应用 SUSFS 补丁及各内核版本所需的上下文修复
#
# 依赖环境变量：
#   ANDROID_VERSION KERNEL_VERSION KSU_VARIANT OS_PATCH_LEVEL SUB_LEVEL
#   KERNEL_ROOT SUSFS4KSU KERNEL_PATCHES LEGACY_SUKISU_CONFIG
# 调用前必须将工作目录设为 $KERNEL_ROOT
set -eo pipefail

echo "应用 SUSFS 补丁..."

SUSFS_PATCH="50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch"
cp "$SUSFS4KSU/kernel_patches/$SUSFS_PATCH" ./common/
cp "$SUSFS4KSU"/kernel_patches/fs/* ./common/fs/
cp "$SUSFS4KSU"/kernel_patches/include/linux/* ./common/include/linux/

case "$KSU_VARIANT" in
  "SukiSU"|"BakaSU")
    echo "SukiSU/BakaSU 使用内置 SUSFS 支持"
    ;;
  "FinaSU")
    echo "FinaSU 使用 susfs4ksu 官方内核侧集成补丁（10_enable + drift-fixes 已在前置步骤应用）"
    ;;
esac

cd "$KERNEL_ROOT/common"
CURRENT_SUB="$SUB_LEVEL"
if [[ ! "$CURRENT_SUB" =~ ^[0-9]+$ ]]; then
  CURRENT_SUB=99999
fi

# 兼容缺少 VMA padding 接口的 5.10.66～209、5.15.74～144 和 6.1.25～68
if grep -qF 'VMA_PAD_START(vma)' "$SUSFS_PATCH" \
  && ! grep -Rqs 'VMA_PAD_START' ./include/linux; then
  echo "目标内核未提供 VMA_PAD_START，使用 vma->vm_end 兼容 SUSFS OPEN_REDIRECT"
  sed -i 's/VMA_PAD_START(vma)/vma->vm_end/g' "$SUSFS_PATCH"
fi

adjust_legacy_fdinfo_context() {
  sed -i '/^[[:space:]]*\/\*$/,/^[[:space:]]*u32 mask = mark->mask & IN_ALL_EVENTS;$/d' fs/notify/fdinfo.c
  perl -i -pe 's/\bmask,\s*mark->ignored_mask/inotify_mark_user_mask(mark)/g' fs/notify/fdinfo.c
  perl -i -pe 's/ignored_mask:%x/ignored_mask:0/g' fs/notify/fdinfo.c
}

restore_legacy_fdinfo_context() {
  perl -i -pe 's/^(\s+if \(inode\) \{)/$1\n\t\t\/\*\n\t\t * IN_ALL_EVENTS represents all of the mask bits\n\t\t * that we expose to userspace.  There is at\n\t\t * least one bit (FS_EVENT_ON_CHILD) which is\n\t\t * used only internally to the kernel.\n\t\t *\/\n\t\tu32 mask = mark->mask & IN_ALL_EVENTS;/m' fs/notify/fdinfo.c
  perl -i -pe 's/\binotify_mark_user_mask\(mark\)/mask, mark->ignored_mask/g' fs/notify/fdinfo.c
  perl -i -pe 's/ignored_mask:0/ignored_mask:%x/g' fs/notify/fdinfo.c
}

# 临时调整旧内核源码上下文，使 SUSFS 主补丁可以匹配
if [[ "$ANDROID_VERSION" == "android12" && "$KERNEL_VERSION" == "5.10" ]]; then
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -le 43 ]]; then
    echo "临时调整 Android 12 5.10 base.c 上下文"
    perl -i -pe 's/(int|size_t)\s+this_len\s*=\s*min_t\s*\(\s*\1\s*,/size_t this_len = min_t(size_t,/;' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 117 ]]; then
    echo "临时调整 Android 12 5.10 fdinfo.c 上下文"
    adjust_legacy_fdinfo_context
  fi
fi

if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  if [[ "$CURRENT_SUB" -le 41 ]]; then
    echo "临时调整 Android 13 5.15 namespace.c/open.c/fdinfo.c 上下文"
    if ! grep -qF '#include <linux/mnt_idmapping.h>' fs/namespace.c; then
      sed -i '/^#include <linux\/shmem_fs.h>$/a #include <linux/mnt_idmapping.h>' fs/namespace.c
    fi
    if ! grep -qF '#include <linux/mnt_idmapping.h>' fs/open.c; then
      sed -i '/^#include <linux\/compat.h>$/a #include <linux/mnt_idmapping.h>' fs/open.c
    fi
    adjust_legacy_fdinfo_context
  fi
  if [[ "$OS_PATCH_LEVEL" == "lts" ]]; then
    echo "临时调整 Android 13 5.15 LTS 头文件上下文"
    sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c
    sed -i '/^#include <trace\/hooks\/mm.h>$/d' fs/proc/task_mmu.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  if [[ "$CURRENT_SUB" -le 25 ]] && ! grep -qF '#include <trace/hooks/sched.h>' fs/proc/base.c; then
    echo "临时调整 Android 14 6.1 sched.h 上下文"
    sed -i '/^#include <trace\/events\/oom.h>$/a #include <trace/hooks/sched.h>' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 141 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/proc/base.c; then
    echo "临时调整 Android 14 6.1 dma-buf.h 上下文"
    sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -ge 157 ]]; then
    echo "临时调整 Android 14 6.1 namespace.c 上下文"
    sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  if [[ "$CURRENT_SUB" -le 92 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/proc/base.c; then
    echo "临时调整 Android 15 6.6 base.c 上下文"
    sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 57 ]] && ! grep -qF '#include <linux/zswap.h>' mm/memory.c; then
    echo "临时调整 Android 15 6.6 memory.c 上下文"
    sed -i '/^#include <linux\/sched\/sysctl.h>$/a #include <linux/zswap.h>' mm/memory.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  if [[ "$CURRENT_SUB" -ge 58 ]]; then
    echo "临时调整 Android 16 6.12 exec.c 上下文"
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/exec.c
  fi
fi

# 新版内核在 super.c 的 internal.h 之后新增了 trace/hooks/fs.h，
# 旧版 SUSFS 主补丁以 thaw_super_locked 为上下文插入 extern 声明，会整段被拒绝；
# 上游 2026-09-15 起已把声明挪到 unnamed_dev_ida 之后，不再依赖这段上下文，
# 但 ShirkNeko fork 尚未同步（固定提交的旧版补丁不改 super.c），只对旧版补丁做临时调整
SUPER_FS_H_REMOVED=""
if grep -q '^ static int thaw_super_locked' "$SUSFS_PATCH" \
  && grep -qF '#include <trace/hooks/fs.h>' fs/super.c; then
  echo "临时调整 super.c 上下文"
  sed -i '/^#include <trace\/hooks\/fs.h>$/,+1d' fs/super.c
  SUPER_FS_H_REMOVED=1
fi

patch -p1 < "$SUSFS_PATCH" || true

# ==================== SukiSU builtin 新 selinux_hide 模型适配（services.c 跳板符号） ====================
# SukiSU-Ultra builtin 2026-05-29 (5fb0c079) 同步 tiann/KernelSU 的 SELinux 新检测
# 修复后，feature/selinux_hide.c 在 >=6.6 分支把 security_dump_masked_av_fn /
# context_struct_compute_av_fn 声明为 extern 函数——上游预期由 services.c 补丁提供
# 这两个跳板符号（builtin c32094a4 提交说明），但 SUSFS 主补丁只在 services.c 提供
# my_security_compute_av_user，不含这两个符号，导致 6.6/6.12 全部 SUSFS 构建在
# vmlinux 链接阶段报：
#   ld.lld: error: undefined symbol: context_struct_compute_av_fn
# 在 services.c 末尾补上两个跳板（对同名 static 函数的薄封装，与上游预期形态一致）；
# 仅当检测到 builtin 的 extern 引用且 services.c 尚无跳板时追加，
# 上游自行提供后按内容检测自动跳过，幂等。
KSU_HIDE_FILE="$KERNEL_ROOT/KernelSU/kernel/feature/selinux_hide.c"
SEC_SERVICES="security/selinux/ss/services.c"
if [ -f "$KSU_HIDE_FILE" ] && grep -q 'extern void context_struct_compute_av_fn' "$KSU_HIDE_FILE" \
  && [ -f "$SEC_SERVICES" ] && ! grep -q 'void context_struct_compute_av_fn(' "$SEC_SERVICES"; then
  if ! grep -q 'static void context_struct_compute_av(' "$SEC_SERVICES"; then
    echo "::error::services.c 缺少 static context_struct_compute_av，无法生成 SukiSU 跳板符号"
    exit 1
  fi
  echo "补齐 SukiSU builtin selinux_hide 所需的 services.c 跳板符号..."
  python3 - "$SEC_SERVICES" <<'PYEOF'
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8", errors="surrogateescape").read()
if "void context_struct_compute_av_fn(" in src:
    sys.exit(0)
tramp = (
    "\n"
    "/* Trampolines for SukiSU-Ultra builtin selinux_hide (KSU_SUSFS builds):\n"
    " * kernel/feature/selinux_hide.c (>=6.6 model) declares *_fn as extern;\n"
    " * provide thin wrappers around the static implementations here. */\n"
    "#ifdef CONFIG_KSU_SUSFS\n"
    "void context_struct_compute_av_fn(struct policydb *policydb,\n"
    "\t\t\t\t  struct context *scontext,\n"
    "\t\t\t\t  struct context *tcontext,\n"
    "\t\t\t\t  u16 tclass,\n"
    "\t\t\t\t  struct av_decision *avd,\n"
    "\t\t\t\t  struct extended_perms *xperms);\n"
    "void context_struct_compute_av_fn(struct policydb *policydb,\n"
    "\t\t\t\t  struct context *scontext,\n"
    "\t\t\t\t  struct context *tcontext,\n"
    "\t\t\t\t  u16 tclass,\n"
    "\t\t\t\t  struct av_decision *avd,\n"
    "\t\t\t\t  struct extended_perms *xperms)\n"
    "{\n"
    "\tcontext_struct_compute_av(policydb, scontext, tcontext, tclass, avd, xperms);\n"
    "}\n"
)
if "static void security_dump_masked_av(" in src:
    tramp += (
        "\n"
        "void security_dump_masked_av_fn(struct policydb *policydb,\n"
        "\t\t\t\tstruct context *scontext,\n"
        "\t\t\t\tstruct context *tcontext,\n"
        "\t\t\t\tu16 tclass,\n"
        "\t\t\t\tu32 permissions,\n"
        "\t\t\t\tconst char *reason);\n"
        "void security_dump_masked_av_fn(struct policydb *policydb,\n"
        "\t\t\t\tstruct context *scontext,\n"
        "\t\t\t\tstruct context *tcontext,\n"
        "\t\t\t\tu16 tclass,\n"
        "\t\t\t\tu32 permissions,\n"
        "\t\t\t\tconst char *reason)\n"
        "{\n"
        "\tsecurity_dump_masked_av(policydb, scontext, tcontext, tclass, permissions, reason);\n"
        "}\n"
    )
else:
    print("::warning::services.c 缺少 static security_dump_masked_av，跳过对应跳板")
tramp += "#endif /* CONFIG_KSU_SUSFS */\n"
open(path, "w", encoding="utf-8", errors="surrogateescape").write(src + tramp)
print("%s: appended *_fn trampolines" % path)
PYEOF
  grep -q 'void context_struct_compute_av_fn(' "$SEC_SERVICES" \
    || { echo "::error::services.c 跳板符号追加后校验失败"; exit 1; }
  echo "services.c: 已提供 context_struct_compute_av_fn / security_dump_masked_av_fn"
fi

# ==================== FinaSU 新 selinux_hide 模型适配 ====================
# 自 FinaSU v0.1.0-preview1 起，kernel/feature/selinux_hide.c 换成了 tiann 新形态：
#   移除 fake_state；统一用 backup_sepolicy + security_context_to_sid_with_policy(..., &orig_sid_p, &orig_rc_p)（8 参）；
#   且该函数内部已做“双策略 + 全局 sidtab 同步”（KernelSU #3877/#3873）。
# 此形态下把 SUSFS 主补丁 <6.6 的 SELinux 代码也从 &fake_state 切到 backup_sepolicy + 8 参 _with_policy，
# 并补上权限检查顺序（df03912f）；sidtab 同步由上游 _with_policy 内置，无需外部再移植。
NEW_MODEL=0
FINASU_SELINUX_HIDE="$KERNEL_ROOT/KernelSU/kernel/feature/selinux_hide.c"
if [ -f "$FINASU_SELINUX_HIDE" ] && ! grep -q 'fake_state' "$FINASU_SELINUX_HIDE"; then
  NEW_MODEL=1
fi
# 触发条件：
#   <6.6（5.10/5.15/6.1）主补丁内联改 selinuxfs 调用点 / selinux_setprocattr，引用 &fake_state；
#   >=6.6（6.6/6.12）主补丁用 backup_sepolicy + 内核侧自含的 my_security_context_to_sid，
#   不引用 fake_state，无需本分支（条件里两个 grep 均不命中，自动跳过）。
# <6.6 必须从 fake_state 切到 backup_sepolicy + 8 参 _with_policy，否则新形态 FinaSU 无
# fake_state 定义会导致 ThinLTO 链接报 undefined symbol: fake_state。
if [ "$NEW_MODEL" = 1 ] && [ -f security/selinux/selinuxfs.c ] \
  && { grep -q 'static ssize_t my_write_context' security/selinux/selinuxfs.c \
       || grep -q '&fake_state' security/selinux/selinuxfs.c; }; then
  echo "检测到 FinaSU 新 selinux_hide 形态：SUSFS <6.6 的 SELinux 代码切换到 backup_sepolicy + 8 参 _with_policy"
  python3 - <<'PYEOF'
import re as _re, sys as _sys

NEW_FS_EXTERNS = (
    "extern struct selinux_policy *backup_sepolicy;\n"
    "extern int security_context_to_sid_with_policy(struct selinux_policy *policy, const char *scontext, u32 scontext_len, u32 *sid, u32 def_sid, gfp_t gfp_flags, u32 *orig_sid_p, int *orig_rc_p);\n"
    "extern int security_sid_to_context_with_policy(struct selinux_policy *policy, u32 sid, char **scontext, u32 *scontext_len);\n"
    "extern void security_compute_av_user_with_policy(struct selinux_policy *policy, u32 ssid, u32 tsid, u16 tclass, struct av_decision *avd);\n"
)
NEW_HK_EXTERNS = (
    "extern struct selinux_policy *backup_sepolicy;\n"
    "extern int security_context_to_sid_with_policy(struct selinux_policy *policy, const char *scontext, u32 scontext_len, u32 *sid, u32 def_sid, gfp_t gfp_flags, u32 *orig_sid_p, int *orig_rc_p);\n"
)

def _sub(path, name, old, new):
    s = open(path, encoding="utf-8", errors="surrogateescape").read()
    n = s.count(old)
    if n != 1:
        print("::warning::%s: %s count=%d (expect 1)" % (path, name, n))
        return
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old, new, 1))
    print("%s: %s OK" % (path, name))

fs = "security/selinux/selinuxfs.c"
_sub(fs, "extern", "extern struct selinux_state fake_state;\n", NEW_FS_EXTERNS)
_sub(fs, "ctx", "security_context_to_sid(&fake_state, buf, size, &sid, GFP_KERNEL)",
     "security_context_to_sid_with_policy(backup_sepolicy, buf, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)")
_sub(fs, "sid2ctx", "security_sid_to_context(&fake_state, sid, &canon, &len)",
     "security_sid_to_context_with_policy(backup_sepolicy, sid, &canon, &len)")
_sub(fs, "scon", "security_context_str_to_sid(&fake_state, scon, &ssid, GFP_KERNEL)",
     "security_context_to_sid_with_policy(backup_sepolicy, scon, strlen(scon), &ssid, SECSID_NULL, GFP_KERNEL, NULL, NULL)")
_sub(fs, "tcon", "security_context_str_to_sid(&fake_state, tcon, &tsid, GFP_KERNEL)",
     "security_context_to_sid_with_policy(backup_sepolicy, tcon, strlen(tcon), &tsid, SECSID_NULL, GFP_KERNEL, NULL, NULL)")
_sub(fs, "av", "security_compute_av_user(&fake_state, ssid, tsid, tclass, &avd)",
     "security_compute_av_user_with_policy(backup_sepolicy, ssid, tsid, tclass, &avd)")

hk = "security/selinux/hooks.c"
_sub(hk, "extern", "extern struct selinux_state fake_state;\n", NEW_HK_EXTERNS)

# <6.6 形态：resolve(&fake_state, value) -> _with_policy(8 参)
#   6.1 主补丁为多行 &sid；5.15 主补丁为单行 &tmp_sid。两种都归一化。
_hs = open(hk, encoding="utf-8", errors="surrogateescape").read()
_hs, _n = _re.subn(r"security_context_to_sid\(&fake_state, value, size,\s*\n\s*&sid, GFP_KERNEL\)",
                   "security_context_to_sid_with_policy(backup_sepolicy, value, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)", _hs)
_hs, _n15 = _re.subn(r"security_context_to_sid\(&fake_state, value, size, &tmp_sid, GFP_KERNEL\)",
                     "security_context_to_sid_with_policy(backup_sepolicy, value, size, &tmp_sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)", _hs)
print("%s: setprocattr.ctx <6.6=%d/%d" % (hk, _n, _n15))
open(hk, "w", encoding="utf-8", errors="surrogateescape").write(_hs)

# >=6.6 形态：把已有的 6 参 _with_policy 声明/调用补成 8 参（新模型签名）
#   6.6 主补丁在 security/selinux/{hooks,selinuxfs}.c 里自带 6 参 extern 声明，
#   只把调用补成 8 参会报 "too many arguments to function call, expected 6, have 8"。
#   因此 extern 声明必须与调用一起改成 8 参（新 FinaSU 的定义是 8 参）。
for _lab, _f in (("selinuxfs", fs), ("hooks", hk)):
    _s = open(_f, encoding="utf-8", errors="surrogateescape").read()
    # (?!, NULL, NULL) 保证幂等：<6.6 已由上文 _sub 切成 8 参的调用不再重复追加
    _s, _n2 = _re.subn(r"(security_context_to_sid_with_policy\(backup_sepolicy,[^;]*?, GFP_KERNEL)\)(?!, NULL, NULL)", r"\1, NULL, NULL)", _s)
    _s, _nd = _re.subn(r"(security_context_to_sid_with_policy\(struct selinux_policy \*policy, const char \*scontext, u32 scontext_len,\s*\n\s*u32 \*sid, u32 def_sid, gfp_t gfp_flags)\);", r"\1, u32 *orig_sid_p, int *orig_rc_p);", _s)
    open(_f, "w", encoding="utf-8", errors="surrogateescape").write(_s)
    print("%s: _with_policy 8-arg normalize=%d decl=%d" % (_lab, _n2, _nd))

_hs = open(hk, encoding="utf-8", errors="surrogateescape").read()
# 主补丁 setprocattr 两种形态：
#   旧形态（~2026-08 前的主补丁）：定义 my_setprocattr，内含无条件 SETCURRENT avc_has_perm
#     —— 需要 rm_early 移除 + seq 重排（df03912f）；
#   现行形态（2026-10 起的主补丁）：内联改 selinux_setprocattr，用 should_check_current +
#     fake_error 门控 —— 权限顺序天然满足 df03912f，且 fake 解析经上文 setprocattr.ctx
#     转换后已走 8 参 _with_policy（sidtab 同步内置），rm_early/seq 无目标代码。
if "should_check_current" in _hs and "fake_error = security_context_to_sid_with_policy(backup_sepolicy, value, size, &tmp_sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)" in _hs:
    print("%s: 主补丁为现行门控形态（should_check_current+fake_error），rm_early_setcurrent/seq 不适用，侧信道语义已覆盖" % hk)
else:
    # 去掉无条件 SETCURRENT 检查（df03912f）：覆盖 <6.6(&selinux_state) 与 >=6.6(无 state) 两种形态
    _removed = False
    for _rm in ("\terror = avc_has_perm(&selinux_state,\n\t\t\t\t     mysid, mysid, SECCLASS_PROCESS,\n\t\t\t\t     PROCESS__SETCURRENT, NULL);\n\n\tif (error)\n\t\treturn error;\n\n",
                "\terror = avc_has_perm(mysid, mysid, SECCLASS_PROCESS,\n\t\t\t\t     PROCESS__SETCURRENT, NULL);\n\n\tif (error)\n\t\treturn error;\n\n"):
        if _hs.count(_rm) == 1:
            _hs = _hs.replace(_rm, "", 1)
            _removed = True
            print("%s: rm_early_setcurrent OK" % hk)
            break
    if not _removed:
        print("::warning::%s: rm_early_setcurrent not matched" % hk)
    # 仅在 backup 解析失败时才检查 SETCURRENT
    _seq_done = False
    for _old2, _new2, _lab in (
        ("\t\terror = security_context_to_sid_with_policy(backup_sepolicy, value, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error)\n\t\t\treturn error;\n",
         "\t\terror = security_context_to_sid_with_policy(backup_sepolicy, value, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error) {\n\t\t\tint perm_error = avc_has_perm(&selinux_state, mysid, mysid, SECCLASS_PROCESS, PROCESS__SETCURRENT, NULL);\n\t\t\treturn perm_error ?: error;\n\t\t}\n", "<6.6"),
        ("\t\terror = security_context_to_sid_with_policy(backup_sepolicy, str, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error)\n\t\t\treturn error;\n",
         "\t\terror = security_context_to_sid_with_policy(backup_sepolicy, str, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error) {\n\t\t\tint perm_error = avc_has_perm(mysid, mysid, SECCLASS_PROCESS, PROCESS__SETCURRENT, NULL);\n\t\t\treturn perm_error ?: error;\n\t\t}\n", ">=6.6")):
        if _hs.count(_old2) == 1:
            _hs = _hs.replace(_old2, _new2, 1)
            _seq_done = True
            print("%s: seq(%s) OK" % (hk, _lab))
            break
    if not _seq_done:
        print("::warning::%s: seq not matched" % hk)
open(hk, "w", encoding="utf-8", errors="surrogateescape").write(_hs)
for _f in (fs, hk):
    _s = open(_f, encoding="utf-8", errors="surrogateescape").read()
    if "fake_state" in _s:
        _sys.stderr.write("::error::%s 仍有 fake_state 残留\n" % _f)
        _sys.exit(1)
PYEOF
  # 仅作信息输出；5.15 主补丁不含 perm_error（权限顺序重排只适配 my_write_context 形态），
  # 这里 grep 可能无命中，必须 || true，否则 set -e 会中断整个补丁步骤。
  grep -n 'backup_sepolicy' security/selinux/selinuxfs.c | head -3 || true
  grep -n 'perm_error' security/selinux/hooks.c | head -3 || true
fi

# ==================== 移植 KernelSU 的 SELinux 隐藏侧信道修复（旧 fake_state 形态）====================
# 仅当 SUSFS 主补丁为旧形态（定义 my_write_context/my_write_access/my_setprocattr）时适用。
# 检测方把 /sys/fs/selinux/{context,access} 与 setprocattr 当 oracle：比对
# 假策略(fake_state)与全局 selinux_state 的 SID、以及权限检查顺序，来识别隐藏。
# SUSFS 主补丁实现的 my_write_context / my_write_access / my_setprocattr 缺这两点，
# 这里按 KernelSU 的做法补齐：
#   - sidtab 同步（KernelSU #3873）：用假策略解析后再同步进全局 sidtab，消除 SID 差异；
#   - 权限检查顺序（KernelSU df03912f）：仅当 backup 解析失败时才做 SETCURRENT 检查。
# 现行主补丁（2026-10 起）已不定义这三个函数：<6.6 的门控内联形态与 NEW_MODEL 分支的
# 8 参 _with_policy 转换（sidtab 同步内置）已覆盖同等的侧信道修复，见下方 else 分支说明。
if [ "${NEW_MODEL:-0}" != 1 ] && [ -f security/selinux/selinuxfs.c ] && grep -q 'static ssize_t my_write_context' security/selinux/selinuxfs.c \
  && [ -f security/selinux/hooks.c ] && grep -q 'static int my_setprocattr' security/selinux/hooks.c; then
  python3 - <<'PYEOF'
import re

def sed(path, name, pat, repl):
    src = open(path, encoding="utf-8", errors="surrogateescape").read()
    new, n = re.subn(pat, repl, src, count=1)
    if n == 0:
        print("::warning::%s: %s not matched (skip)" % (path, name))
        return
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(new)
    print("%s: %s OK" % (path, name))

fs = "security/selinux/selinuxfs.c"
# my_write_context（<6.6 用 fake_state；>=6.6 用 backup_sepolicy 的 _with_policy 解析）
sed(fs, "ctx(<6.6)", r"(\tlength = security_context_to_sid\(&fake_state, buf, size, &sid, GFP_KERNEL\);\n\tif \(length\)\n\t\tgoto out;\n)",
    "\\1\t{\n\t\tu32 tmp_sid;\n\t\t/* FINASU_SIDTAB_SYNC */\n\t\tsecurity_context_to_sid(&selinux_state, buf, size, &tmp_sid, GFP_KERNEL);\n\t}\n")
sed(fs, "ctx(>=6.6)", r"(\tlength = security_context_to_sid_with_policy\(backup_sepolicy, buf, size, &sid, SECSID_NULL, GFP_KERNEL\);\n\tif \(length\)\n\t\tgoto out;\n)",
    "\\1\t{\n\t\tu32 tmp_sid;\n\t\t/* FINASU_SIDTAB_SYNC */\n\t\tsecurity_context_to_sid(buf, size, &tmp_sid, GFP_KERNEL);\n\t}\n")
# my_write_access scon / tcon
sed(fs, "scon(<6.6)", r"(\tlength = security_context_str_to_sid\(&fake_state, scon, &ssid, GFP_KERNEL\);\n\tif \(length\)\n\t\tgoto out;\n)",
    "\\1\t{\n\t\tu32 tmp_sid;\n\t\t/* FINASU_SIDTAB_SYNC */\n\t\tsecurity_context_str_to_sid(&selinux_state, scon, &tmp_sid, GFP_KERNEL);\n\t}\n")
sed(fs, "scon(>=6.6)", r"(\tlength = security_context_to_sid_with_policy\(backup_sepolicy, scon, strlen\(scon\), &ssid, SECSID_NULL, GFP_KERNEL\);\n\tif \(length\)\n\t\tgoto out;\n)",
    "\\1\t{\n\t\tu32 tmp_sid;\n\t\t/* FINASU_SIDTAB_SYNC */\n\t\tsecurity_context_to_sid(scon, strlen(scon), &tmp_sid, GFP_KERNEL);\n\t}\n")
sed(fs, "tcon(<6.6)", r"(\tlength = security_context_str_to_sid\(&fake_state, tcon, &tsid, GFP_KERNEL\);\n\tif \(length\)\n\t\tgoto out;\n)",
    "\\1\t{\n\t\tu32 tmp_sid;\n\t\t/* FINASU_SIDTAB_SYNC */\n\t\tsecurity_context_str_to_sid(&selinux_state, tcon, &tmp_sid, GFP_KERNEL);\n\t}\n")
sed(fs, "tcon(>=6.6)", r"(\tlength = security_context_to_sid_with_policy\(backup_sepolicy, tcon, strlen\(tcon\), &tsid, SECSID_NULL, GFP_KERNEL\);\n\tif \(length\)\n\t\tgoto out;\n)",
    "\\1\t{\n\t\tu32 tmp_sid;\n\t\t/* FINASU_SIDTAB_SYNC */\n\t\tsecurity_context_to_sid(tcon, strlen(tcon), &tmp_sid, GFP_KERNEL);\n\t}\n")

hk = "security/selinux/hooks.c"
# 去掉无条件 SETCURRENT 检查（<6.6 带 &selinux_state；>=6.6 不带）
sed(hk, "rm_early(<6.6)", r"\terror = avc_has_perm\(&selinux_state,\n\t\t\t\t     mysid, mysid, SECCLASS_PROCESS,\n\t\t\t\t     PROCESS__SETCURRENT, NULL\);\n\n\tif \(error\)\n\t\treturn error;\n\n", "")
sed(hk, "rm_early(>=6.6)", r"\terror = avc_has_perm\(mysid, mysid, SECCLASS_PROCESS,\n\t\t\t\t     PROCESS__SETCURRENT, NULL\);\n\n\tif \(error\)\n\t\treturn error;\n\n", "")
# 仅在 backup 解析失败时才检查 SETCURRENT，并同步全局 sidtab
sed(hk, "seq+sync(<6.6)", r"(\t\terror = security_context_to_sid\(&fake_state, value, size,\n\t\t\t\t\t\t&sid, GFP_KERNEL\);\n)\t\tif \(error\)\n\t\t\treturn error;\n",
    "\\1\t\tif (error) {\n\t\t\t/* FINASU_SEQ: 仅当 backup 解析失败时才做 SETCURRENT 检查（KernelSU df03912f） */\n\t\t\tint perm_error = avc_has_perm(&selinux_state, mysid, mysid, SECCLASS_PROCESS, PROCESS__SETCURRENT, NULL);\n\t\t\treturn perm_error ?: error;\n\t\t}\n\t\t{\n\t\t\tu32 tmp_sid;\n\t\t\t/* FINASU_SIDTAB_SYNC (KernelSU #3873) */\n\t\t\tsecurity_context_to_sid(&selinux_state, value, size, &tmp_sid, GFP_KERNEL);\n\t\t}\n")
sed(hk, "seq+sync(>=6.6)", r"(\t\terror = security_context_to_sid_with_policy\(backup_sepolicy, str, size, &sid, SECSID_NULL, GFP_KERNEL\);\n)\t\tif \(error\)\n\t\t\treturn error;\n",
    "\\1\t\tif (error) {\n\t\t\t/* FINASU_SEQ: 仅当 backup 解析失败时才做 SETCURRENT 检查（KernelSU df03912f） */\n\t\t\tint perm_error = avc_has_perm(mysid, mysid, SECCLASS_PROCESS, PROCESS__SETCURRENT, NULL);\n\t\t\treturn perm_error ?: error;\n\t\t}\n\t\t{\n\t\t\tu32 tmp_sid;\n\t\t\t/* FINASU_SIDTAB_SYNC (KernelSU #3873) */\n\t\t\tsecurity_context_to_sid(str, size, &tmp_sid, GFP_KERNEL);\n\t\t}\n")
PYEOF
  # 仅作信息输出；旧形态模式部分失配时 grep 无命中，必须 || true，否则 pipefail 会中断整个补丁步骤
  grep -n 'FINASU_SIDTAB_SYNC' security/selinux/selinuxfs.c | head || true
  grep -n 'FINASU_SIDTAB_SYNC\|FINASU_SEQ' security/selinux/hooks.c | head || true
else
  # 主补丁形态判定：
  #   旧形态定义 my_write_context/my_write_access/my_setprocattr，缺失即异常，保留告警；
  #   现行形态（2026-10 起的主补丁）不再定义这三个函数：<6.6 内联改 selinux_setprocattr /
  #   selinuxfs 调用点（should_check_current+fake_error 门控），>=6.6 用 backup_sepolicy +
  #   my_security_context_to_sid（内核侧自含）。侧信道修复（sidtab 同步 #3873、权限顺序
  #   df03912f）由 NEW_MODEL 分支的 8 参 _with_policy 转换与门控校验覆盖，无需旧形态移植。
  if grep -qE 'static ssize_t my_write_(context|access)' security/selinux/selinuxfs.c 2>/dev/null \
    || grep -q 'static int my_setprocattr' security/selinux/hooks.c 2>/dev/null; then
    echo "::warning::未找到 SUSFS 的 my_write_context/my_setprocattr，跳过 SELinux 侧信道移植"
  else
    echo "SUSFS 主补丁为现行形态（无 my_write_context/my_setprocattr）：侧信道修复由门控校验与 8 参 _with_policy 内置同步覆盖，无需旧形态移植"
  fi
fi

# ==================== SUSFS 路径隐藏回退（跨命名空间 / FUSE） ====================
# susfs_add_sus_path（非 loop）在“调用方命名空间”里 kern_path 解析路径；管理器/ksud 常解析不到
# /storage/emulated 这类 FUSE 路径（-ENOENT），于是规则加不进去、路径隐藏失效。
# 这里加回退：解析失败时自动改走 LOOP 机制（内核 workqueue 在 init 命名空间稍后解析并打标记）。
if [ -f fs/susfs.c ] && grep -qF 'void susfs_add_sus_path(void __user **user_info)' fs/susfs.c \
  && ! grep -qF 'FINASU_SUS_PATH_LOOP_FALLBACK' fs/susfs.c; then
  python3 - <<'PYEOF'
p = "fs/susfs.c"
s = open(p, encoding="utf-8", errors="surrogateescape").read()
old1 = "void susfs_add_sus_path(void __user **user_info) {"
new1 = "void susfs_add_sus_path_loop(void __user **user_info);\n" + old1
if s.count(old1) != 1:
    print("::warning::fs/susfs.c: susfs_add_sus_path 签名不是预期形态，跳过")
else:
    s = s.replace(old1, new1, 1)
    old2 = ("\tif (copy_from_user(&info, (struct st_susfs_sus_path __user*)*user_info, sizeof(info))) {\n"
            "\t\tinfo.err = -EFAULT;\n"
            "\t\tgoto out_copy_to_user;\n"
            "\t}\n\n"
            "\tinfo.err = kern_path(info.target_pathname, LOOKUP_FOLLOW, &path);\n"
            "\tif (info.err) {\n"
            "\t\tSUSFS_LOGE(\"failed opening file '%s'\\n\", info.target_pathname);\n"
            "\t\tgoto out_copy_to_user;\n"
            "\t}\n")
    new2 = ("\tif (copy_from_user(&info, (struct st_susfs_sus_path __user*)*user_info, sizeof(info))) {\n"
            "\t\tinfo.err = -EFAULT;\n"
            "\t\tgoto out_copy_to_user;\n"
            "\t}\n\n"
            "\tinfo.err = kern_path(info.target_pathname, LOOKUP_FOLLOW, &path);\n"
            "\tif (info.err) {\n"
            "\t\tSUSFS_LOGE(\"failed opening '%s' in current ns, fallback to sus_path_loop\\n\", info.target_pathname);\n"
            "\t\t/* FINASU_SUS_PATH_LOOP_FALLBACK: 调用方命名空间解析不到（常见于 /storage/emulated 等 FUSE 路径）时，\n"
            "\t\t   退回 LOOP 机制，交由内核 workqueue 在 init 命名空间稍后解析并重新打标记 */\n"
            "\t\tsusfs_add_sus_path_loop(user_info);\n"
            "\t\treturn;\n"
            "\t}\n")
    if s.count(old2) != 1:
        print("::warning::fs/susfs.c: susfs_add_sus_path 代码形态不是预期，跳过回退")
    else:
        open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old2, new2, 1))
        print("fs/susfs.c: 已加 SUSFS 路径隐藏 LOOP 回退")
PYEOF
  grep -n 'FINASU_SUS_PATH_LOOP_FALLBACK' fs/susfs.c | head
else
  echo "::warning::未找到 fs/susfs.c 的 susfs_add_sus_path，跳过路径隐藏回退"
fi


# ---- 预期冲突处理：上游已包含同款修改的 .rej 剔除，真实缺失的手工补齐 ----

# 1) fs/unicode：ASB 内核已包含上游 "unicode: don't special case ignorable code
#    points" 提交，主补丁删除 ignore_init / 重生成 utf8data 的 hunk 已天然满足
if [[ -f fs/unicode/mkutf8data.c.rej ]] && ! grep -q 'ignore_init' fs/unicode/mkutf8data.c; then
  echo "fs/unicode .rej 为上游已包含同款修改，剔除预期冲突文件"
  rm -f fs/unicode/*.rej
fi

# 2) mm/rmap.c：6.6.127+ 已包含 huge_pmd_unshare 的 tlb 化改造
if [[ -f mm/rmap.c.rej ]] && grep -q 'tlb_gather_mmu_vma' mm/rmap.c; then
  echo "mm/rmap.c .rej 为上游已包含同款修改，剔除预期冲突文件"
  rm -f mm/rmap.c.rej
fi

# 3) fs/proc/task_mmu.c（6.12.69+）：show_smap 重构（vma_pages → vma_data_pages）
#    导致 SUS_MAP 检查 hunk 上下文失配被拒，属于真实缺失，手工补回
if [[ -f fs/proc/task_mmu.c.rej ]] \
  && grep -qF 'static int show_smap(struct seq_file *m, void *v)' fs/proc/task_mmu.c; then
  SHOW_SMAP_BODY="$(sed -n '/^static int show_smap(struct seq_file \*m, void \*v)/,/^}/p' fs/proc/task_mmu.c)"
  if [[ -n "$SHOW_SMAP_BODY" ]] && ! grep -qF 'SUSFS_IS_INODE_SUS_MAP' <<< "$SHOW_SMAP_BODY"; then
    echo "为 show_smap 手工补入 SUS_MAP 检查（6.12.69+ 上下文漂移）"
    perl -0pi -e 's/(static int show_smap\(struct seq_file \*m, void \*v\)\n\{\n\tstruct vm_area_struct \*vma = v;\n\tstruct mem_size_stats mss = \{\};\n)/$1\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n/' fs/proc/task_mmu.c
    if ! grep -qF 'SUSFS_IS_INODE_SUS_MAP' fs/proc/task_mmu.c; then
      echo "::error::show_smap SUS_MAP 检查手工补丁失败，请人工核对 fs/proc/task_mmu.c"
      exit 1
    fi
    rm -f fs/proc/task_mmu.c.rej
  fi
fi

# 为尚未提供 SU 会话 FD 接口的 SukiSU/BakaSU 恢复旧版 exec hook 行为
EXEC_HELPER=""
if [[ "$KSU_VARIANT" == SukiSU* || "$KSU_VARIANT" == "BakaSU" || "$KSU_VARIANT" == "FinaSU" ]]; then
  if grep -qF 'ksu_install_su_fd();' fs/exec.c; then
    EXEC_HELPER="ksu_install_su_fd"
  elif grep -qF 'ksu_handle_post_execveat_sucompat(' fs/exec.c; then
    EXEC_HELPER="ksu_handle_post_execveat_sucompat"
  fi
fi
if [[ -n "$EXEC_HELPER" ]] \
  && ! grep -RqsE --include='*.c' "^[[:space:]]*int[[:space:]]+${EXEC_HELPER}[[:space:]]*\(" "$KERNEL_ROOT/KernelSU/kernel"; then
  echo "$KSU_VARIANT 尚未提供 $EXEC_HELPER，恢复旧版 exec hook"
  sed -i '/^extern int ksu_install_su_fd(void);$/d' fs/exec.c
  sed -i '/^extern int ksu_handle_post_execveat_sucompat(/,+1d' fs/exec.c
  sed -i 's/is_su_session = !\(ksu_handle_execveat[^;]*;\)/\1/' fs/exec.c
  sed -i '/^[[:space:]]*bool is_su_session = false;$/d' fs/exec.c
  sed -i '/^[[:space:]]*if (unlikely(is_su_session && retval >= 0))$/,+1d' fs/exec.c
  sed -i '/^[[:space:]]*if (unlikely(is_su_session))$/,+1d' fs/exec.c
  sed -i '/^#ifdef CONFIG_KSU_SUSFS$/N;/^#ifdef CONFIG_KSU_SUSFS\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS$/d' fs/exec.c
  if grep -qE 'ksu_install_su_fd|ksu_handle_post_execveat_sucompat|is_su_session' fs/exec.c; then
    echo "::error::$KSU_VARIANT exec hook 结构已变化，无法完成兼容修复"
    exit 1
  fi
fi

# 上游 5.10 主补丁把 susfs_sus_kstat_spoof_vfs_statfs 的 extern 声明放在了
# fs/statfs.c 的使用点之后（vfs_statfs 之前），clang -Werror 报隐式声明；
# 声明属于 SUSFS 接口，直接补进公共头 include/linux/susfs_def.h：
# 不依赖 statfs.c 内锚点与行号比较，声明重复合法，上游后续自行修复也不冲突。
# 注意：FinaSU 的 setuid_hook.c / sucompat.c 会在仅有 <linux/types.h> 等基础
# 头文件时就包含 susfs_def.h，此时 struct kstatfs 尚未声明，原型内引入新
# struct 标签会触发 clang -Werror,-Wvisibility（上游内核构建日志实证），
# 因此必须连同 struct 前置声明一起插入。
SUSFS_DEF_H="$KERNEL_ROOT/common/include/linux/susfs_def.h"
if [[ -f fs/statfs.c ]] && grep -qF 'susfs_sus_kstat_spoof_vfs_statfs(' fs/statfs.c \
  && [[ -f "$SUSFS_DEF_H" ]] \
  && ! grep -qF 'susfs_sus_kstat_spoof_vfs_statfs(' "$SUSFS_DEF_H"; then
  echo "将 susfs_sus_kstat_spoof_vfs_statfs 声明补入 include/linux/susfs_def.h"
  sed -i '/^#endif \/\/ #ifndef KSU_SUSFS_DEF_H$/i struct inode;\nstruct kstatfs;\nextern int susfs_sus_kstat_spoof_vfs_statfs(struct inode *inode, struct kstatfs *buf, bool *is_fuse);' "$SUSFS_DEF_H"
fi

# 上游 susfs.c 直接调用 security_sb_statfs 却没有包含 linux/security.h，
# 5.15+ 靠其他头文件间接带入，5.10 没有这条路径，clang -Werror 报隐式声明；缺失时补上
if [[ -f fs/susfs.c ]] && grep -qF 'security_sb_statfs(' fs/susfs.c \
  && ! grep -qF '#include <linux/security.h>' fs/susfs.c; then
  echo "为 susfs.c 补充 linux/security.h 头文件"
  sed -i '0,/^#include <linux\/fs.h>$/s//#include <linux\/fs.h>\n#include <linux\/security.h>/' fs/susfs.c
fi

# 在编译前报告 SUSFS 主补丁产生的冲突文件
SUSFS_REJ_COUNT=$(find . -name '*.rej' | wc -l)
if [ "$SUSFS_REJ_COUNT" -gt 0 ]; then
  echo "::warning title=SUSFS 补丁冲突::SUSFS 主补丁产生了 ${SUSFS_REJ_COUNT} 个 .rej 冲突文件，可能导致后续编译失败（详见 Rejects 产物）"
  find . -name '*.rej' -print
fi

# 还原仅用于补丁匹配的临时源码调整
if [[ "$ANDROID_VERSION" == "android12" && "$KERNEL_VERSION" == "5.10" ]]; then
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -le 43 ]]; then
    echo "还原 Android 12 5.10 base.c 临时调整"
    sed -i 's/^size_t this_len = min_t(size_t, count, PAGE_SIZE);$/int this_len = min_t(int, count, PAGE_SIZE);/' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 117 ]]; then
    echo "还原 Android 12 5.10 fdinfo.c 临时调整"
    restore_legacy_fdinfo_context
  fi
fi

if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  if [[ "$CURRENT_SUB" -le 41 ]]; then
    echo "还原 Android 13 5.15 临时调整"
    sed -i '/#include <linux\/mnt_idmapping.h>$/d' fs/namespace.c
    sed -i '/#include <linux\/mnt_idmapping.h>$/d' fs/open.c
    restore_legacy_fdinfo_context
    sed -i 's|i_uid_into_mnt(i_user_ns(&fi->inode), &fi->inode).val|i_uid_into_mnt(\&init_user_ns, \&fi->inode).val|g' fs/susfs.c
    sed -i 's|i_uid_into_mnt(i_user_ns(inode), inode).val|i_uid_into_mnt(\&init_user_ns, inode).val|g' fs/susfs.c
  fi
  if [[ "$OS_PATCH_LEVEL" == "lts" ]]; then
    echo "还原 Android 13 5.15 LTS 头文件上下文"
    if ! grep -qF '#include <trace/hooks/blk.h>' fs/namespace.c; then
      sed -i '/^#include "internal.h"$/a #include <trace/hooks/blk.h>' fs/namespace.c
    fi
    if ! grep -qF '#include <trace/hooks/mm.h>' fs/proc/task_mmu.c; then
      sed -i '/^#include <linux\/pkeys.h>$/a #include <trace/hooks/mm.h>' fs/proc/task_mmu.c
    fi
  fi
fi

if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  if [[ "$CURRENT_SUB" -le 25 ]]; then
    sed -i '/^#include <trace\/hooks\/sched.h>$/d' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 141 ]]; then
    echo "还原 Android 14 6.1 base.c 临时调整"
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -ge 157 ]] && ! grep -qF '#include <trace/hooks/blk.h>' fs/namespace.c; then
    echo "还原 Android 14 6.1 namespace.c 临时调整"
    sed -i '/^#include "internal.h"$/a #include <trace/hooks/blk.h>' fs/namespace.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  if [[ "$CURRENT_SUB" -le 92 ]]; then
    echo "还原 Android 15 6.6 base.c 临时调整"
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 57 ]]; then
    echo "还原 Android 15 6.6 memory.c 临时调整"
    sed -i '/^#include <linux\/zswap.h>$/d' mm/memory.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  if [[ "$CURRENT_SUB" -ge 58 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/exec.c; then
    echo "还原 Android 16 6.12 exec.c 临时调整"
    sed -i '0,/^#include /s//#include <linux\/dma-buf.h>\n&/' fs/exec.c
  fi
fi

if [[ -n "$SUPER_FS_H_REMOVED" ]] \
  && ! grep -qF '#include <trace/hooks/fs.h>' fs/super.c; then
  echo "还原 super.c 临时调整"
  sed -i '/^#include "internal.h"$/a #include <trace/hooks/fs.h>' fs/super.c
fi

fix_missing_vm_flags_clear() {
  if [[ "$OS_PATCH_LEVEL" == "2024-11" ]] && grep -qF 'vm_flags_clear(new_vma, VM_PAD_MASK);' ./mm/mmap.c; then
    sed -i 's/vm_flags_clear(new_vma, VM_PAD_MASK);/new_vma->vm_flags \&= ~VM_PAD_MASK;/' ./mm/mmap.c
  fi
}

fix_task_mmu_show_pad() {
  local max_sub="$1"
  local excluded_patch_level="${2:-}"

  # 仅固定旧版 SUSFS 补丁会引入 goto show_pad，最新版已不再包含该代码
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -le "$max_sub" ]] \
    && { [[ -z "$excluded_patch_level" ]] || [[ "$OS_PATCH_LEVEL" != "$excluded_patch_level" ]]; }; then
    sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c
  fi
}

# Android 12 - 5.10 修复
if [[ "$ANDROID_VERSION" == "android12" && "$KERNEL_VERSION" == "5.10" ]]; then
  # 修复 2024-11 分支: mmap.c 调用了 vm_flags_clear()，但同分支 mm.h 未提供 helper
  fix_missing_vm_flags_clear
  fix_task_mmu_show_pad 209
fi

# Android 13 - 5.15 修复
  if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  # 修复 2024-11 分支: mmap.c 调用了 vm_flags_clear()，但同分支 mm.h 未提供 helper
  fix_missing_vm_flags_clear
  fix_task_mmu_show_pad 148 "2024-05"
fi

# Android 14 - 6.1 修复
if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  fix_task_mmu_show_pad 75 "2024-05"
fi

# Android 15 - 6.6 修复
if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  # 修复老版 SukiSU 6.6.50~6.6.58: task_mmu.c 打入 SUSFS 后使用 vma，但旧源码没有对应声明
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -ge 50 && "$CURRENT_SUB" -le 58 ]] \
    && grep -qF 'vma = find_vma(mm, start_vaddr);' ./fs/proc/task_mmu.c; then
    TASK_MMU_PATCH="$KERNEL_PATCHES/wild/archived/susfs_fix_patches/v2.1.0/a15-6.6/task_mmu.c.patch"
    if [ ! -f "$TASK_MMU_PATCH" ]; then
      echo "::error::补丁不存在: $TASK_MMU_PATCH"
      exit 1
    fi
    cp "$TASK_MMU_PATCH" ./
    if patch -p1 --dry-run < task_mmu.c.patch >/dev/null 2>&1; then
      patch -p1 --no-backup-if-mismatch < task_mmu.c.patch
      echo "已应用 Android 15 6.6.50~6.6.58 task_mmu.c 归档修复补丁"
    else
      echo "Android 15 6.6.50~6.6.58 task_mmu.c 归档修复补丁已应用或当前上下文不匹配，跳过"
    fi
  fi
fi

# Android 16 - 6.12 修复
if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  # 固定旧版 SukiSU 在 6.12 上会重复定义 setresuid hook
  SETUID_HOOK="$KERNEL_ROOT/common/drivers/kernelsu/setuid_hook.c"
  if [[ -n "$LEGACY_SUKISU_CONFIG" && -f "$SETUID_HOOK" ]] \
    && grep -qF 'defined(CONFIG_KSU_MANUAL_HOOK))' "$SETUID_HOOK"; then
    sed -i 's/defined(CONFIG_KSU_MANUAL_HOOK))/!defined(CONFIG_KSU_SUSFS) \&\& defined(CONFIG_KSU_MANUAL_HOOK))/' "$SETUID_HOOK"
    echo "已修复 setuid_hook.c 重复定义问题"
  fi
fi
