#!/usr/bin/env bash
# SukiSU builtin 分支内核 UAPI 动态同步（对齐官方 main 分支管理器）
#
# 背景：
#   builtin 分支（内建+SUSFS 产品线）与官方 main 分支相互独立，
#   官方管理器 APK 始终按 main 分支构建。main 的 uapi/supercall.h
#   抬升 KERNEL_SU_UAPI_VERSION 时（如 3b60791 把 UAPI 升到 6 并新增
#   KSU_IOCTL_LOOKUP_SYMBOLS / KSU_GET_INFO_FLAG_PREINIT），builtin 检出
#   的内核 UAPI 落后于管理器，管理器 requiresNewKernel = true，
#   首页报"需要更新内核"（Natives.kt: managerUAPIVersion > kernelUAPIVersion）。
#
# 本脚本动态移植：读取官方 main 的 uapi/supercall.h，将其相对 builtin
# 检出缺失的「UAPI 常量声明 + KSU_GET_INFO_FLAG_* 位 + 新增 ioctl 常量 +
# struct ksu_lookup_symbols_cmd」按官方原文追加到 builtin 头文件，
# UAPI 号抬到与 main 一致。内核侧配套能力（LOOKUP_SYMBOLS 处理器、
# symbol_resolver）由 build.yml 在本脚本之后以独立内容检测步骤注入。
#
# 移植均为内容检测：已包含则跳过，重复执行幂等；上游 builtin 自行同步
# UAPI 后同样自动跳过。
#
# 用法: sync_uapi.sh [KernelSU 目录]（调用方工作目录需为 $KERNEL_ROOT，
#       需可访问官方仓库 raw.githubusercontent.com）

set -eo pipefail

KSU_DIR="${1:-KernelSU}"

fail() {
  if [ "$SKIP_INCOMPATIBLE" = "true" ]; then
    echo "::warning title=SukiSU UAPI 同步已跳过::$1"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "" >> "$GITHUB_STEP_SUMMARY"
      echo "> ⏭️ **SukiSU UAPI 同步** 已自动跳过：$1（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
  fi
  echo "::error::$1"
  exit 1
}

[ -d "$KSU_DIR" ] || fail "未找到 KernelSU 目录: $KSU_DIR"

COMPAT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# builtin 分支: kernel/include/uapi/supercall.h；main 分支: uapi/supercall.h
UAPI_FILE=""
for f in "$KSU_DIR/kernel/include/uapi/supercall.h" "$KSU_DIR/uapi/supercall.h"; do
  if [ -f "$f" ]; then
    UAPI_FILE="$f"
    break
  fi
done
[ -n "$UAPI_FILE" ] || fail "未找到 supercall.h，SukiSU 源码布局可能已变化"

read_uapi() {
  grep -ohE 'KERNEL_SU_UAPI_VERSION[^0-9]*[0-9]+' "$1" | grep -oE '[0-9]+' | tail -n 1
}

# 取官方 main 的 supercall.h（web 布局，UAPI 定义以 static const 发布）
MAIN_URL="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/uapi/supercall.h"
MAIN_FILE=$(mktemp)
MAIN_JSON=""
for ATTEMPT in 1 2 3; do
  if curl -sL --fail --max-time 60 -o "$MAIN_FILE" "$MAIN_URL" && [ -s "$MAIN_FILE" ]; then
    break
  fi
  echo "拉取官方 main supercall.h 失败，重试 ($ATTEMPT/3)..."
  sleep 5
done
[ -s "$MAIN_FILE" ] || fail "无法拉取官方 main uapi/supercall.h，UAPI 同步中止"

MAIN_UAPI=$(read_uapi "$MAIN_FILE")
CUR_UAPI=$(read_uapi "$UAPI_FILE")
echo "官方 main UAPI 版本: ${MAIN_UAPI:-未知}, builtin 检出当前 UAPI 版本: ${CUR_UAPI:-未知}"
[ -n "$MAIN_UAPI" ] || fail "官方 main supercall.h 中未解析到 KERNEL_SU_UAPI_VERSION"

if [ "${CUR_UAPI:-0}" -ge "$MAIN_UAPI" ]; then
  echo "builtin 检出 UAPI >= 官方 main（$CUR_UAPI >= $MAIN_UAPI），无需同步，跳过"
  rm -f "$MAIN_FILE"
  exit 0
fi

python3 - "$UAPI_FILE" "$MAIN_FILE" <<'PYEOF'
import sys, re

uapi_path, main_path = sys.argv[1], sys.argv[2]
uapi = open(uapi_path, encoding="utf-8", errors="surrogateescape").read()
main = open(main_path, encoding="utf-8", errors="surrogateescape").read()

def read_num(text, name):
    m = re.search(re.escape(name) + r"[^0-9]*(\d+)", text)
    return int(m.group(1)) if m else None

main_ver = read_num(main, "KERNEL_SU_UAPI_VERSION")
cur_ver = read_num(uapi, "KERNEL_SU_UAPI_VERSION")
if not main_ver:
    print("::error::官方 main supercall.h 缺少 KERNEL_SU_UAPI_VERSION")
    sys.exit(1)

changed = []

# 1) 按官方值移植 builtin 缺失的常量（含抬升后的 KERNEL_SU_UAPI_VERSION、
#    EVENT_*、KSU_GET_INFO_FLAG_*、新 ioctl 常量、KSU_LOOKUP_SYMBOLS_MAX 等）。
#    声明形式跟随 builtin 现有的 DECLARE 宏（非 BINDGEN 下展开为 enum，
#    是编译期常量，dispatch.c 的 static 处理表才能引用；main 的 static const
#    形式在 builtin 的 static 初始化器上下文会报
#    "initializer element is not a compile-time constant"）。
#    逐常量移植而非整文件替换：builtin 头还有独立演化内容
#    （DECLARE 宏、__user 注记的 ksu_kpm_cmd 等），整替换会互相覆盖。
def parse_decls(text):
    decls = {}
    for m in re.finditer(r"^static const (\w[\w\s\*]*?)\b(\w+)\s*=\s*([^;\n]+);", text, re.M):
        decls.setdefault(m.group(2), (m.group(1), m.group(3)))
    return decls

main_decls = parse_decls(main)
has_declare = "#define DECLARE" in uapi

# 2) 移植 builtin 缺失的 struct 定义（如 ksu_lookup_symbols_cmd /
#    ksu_set_spoof_version_cmd）。struct 必须先于引用它的 _IOW 常量声明，
#    且插入点需在 include guard 内（supercall.h 会被 ksu.c / dynamic_manager.c
#    多次 include，文件尾 #endif 之外的内容每次 include 都会重复定义）。
struct_re = re.compile(r"^struct (\w+) \{(?:[^{}])*?\};", re.M | re.S)
main_structs = []
for m in struct_re.finditer(main):
    main_structs.append((m.group(1), m.group(0)))

missing_structs = [(n, t) for n, t in main_structs if not re.search(r"struct\s+" + re.escape(n) + r"\s*\{", uapi)]
missing_decls = {n: v for n, v in main_decls.items() if not re.search(r"\b" + re.escape(n) + r"\b", uapi)}

# 统一插入点：flag 区块之后（guard 内、DECLARE 宏之后、struct/常量使用之前）
anchor = re.search(r"(DECLARE\(__u32, KSU_GET_INFO_FLAG_PR_BUILD[^\n]*\n|static const __u32 KSU_GET_INFO_FLAG_PR_BUILD[^\n]*\n)", uapi)
if not anchor:
    anchor = re.search(r"(DECLARE\(__u32, KERNEL_SU_UAPI_VERSION[^\n]*\n|static const __u32 KERNEL_SU_UAPI_VERSION[^\n]*\n)", uapi)
if not anchor:
    print("::error::builtin supercall.h 缺常量/struct 插入锚点（UAPI/FLAG 区块）")
    sys.exit(1)
pos = anchor.end()

block = "\n// synced from SukiSU-Ultra main uapi/supercall.h (dynamic UAPI sync)\n"
# struct 先插（同名的 _IOW 常量在插入块里引用它们）
for sname, text in missing_structs:
    block += text + "\n"
    changed.append("struct " + sname)
for name, (ctype, value) in missing_decls.items():
    if has_declare:
        block += "DECLARE(%s, %s, %s);\n" % (ctype, name, value)
    else:
        block += "static const %s %s = %s;\n" % (ctype, name, value)
    changed.append(name)
if missing_decls:
    block += "\n"

uapi = uapi[:pos] + block + uapi[pos:]

# 3) 抬升 UAPI 号到官方值
if cur_ver is not None and cur_ver < main_ver:
    uapi = re.sub(
        r"((?:DECLARE\(__u32, KERNEL_SU_UAPI_VERSION|static const __u32 KERNEL_SU_UAPI_VERSION)[^\n]*?)\b%d\b" % cur_ver,
        r"\g<1>%d" % main_ver,
        uapi, count=1)
    changed.append("KERNEL_SU_UAPI_VERSION %d -> %d" % (cur_ver, main_ver))

if not changed:
    print("supercall.h: 无需移植（UAPI 号与常量均已包含）")
else:
    open(uapi_path, "w", encoding="utf-8", errors="surrogateescape").write(uapi)
    for c in changed:
        print("supercall.h: 移植 %s" % c)
PYEOF

# ---------------- 内核侧配套能力注入（LOOKUP_SYMBOLS / symbol_resolver） ----------------
# UAPI >= 6 时管理器会探测 KSU_IOCTL_LOOKUP_SYMBOLS（热装模块符号绑定用）。
# 该能力依赖 main 分支的 infra/symbol_resolver，builtin 检出缺少它，按内容
# 检测注入：分发 resolver 源码 + 补内核 include + 接线 do_lookup_symbols。
if grep -q 'KSU_IOCTL_LOOKUP_SYMBOLS' "$UAPI_FILE" 2>/dev/null; then
  RESOLVER_C="$KSU_DIR/kernel/infra/symbol_resolver.c"
  RESOLVER_H="$KSU_DIR/kernel/infra/symbol_resolver.h"
  if [ ! -f "$RESOLVER_C" ] || ! grep -q 'ksu_lookup_kernel_symbols' "$RESOLVER_C" 2>/dev/null; then
    echo "注入 infra/symbol_resolver (main 分支 UAPI6 符号批量解析)..."
    cp "$COMPAT_DIR/symbol_resolver.h" "$RESOLVER_H" || fail "symbol_resolver.h 分发失败"
    cp "$COMPAT_DIR/symbol_resolver.c" "$RESOLVER_C" || fail "symbol_resolver.c 分发失败"
    grep -q 'ksu_lookup_kernel_symbols' "$RESOLVER_C" || fail "symbol_resolver.c 分发后校验失败"
  else
    echo "infra/symbol_resolver 已存在，跳过分发"
  fi

  # builtin 以 ksu.c unity build 编译（kernel_includes.h 聚合内核头），
  # resolver 依赖的 bsearch/sort/kallsyms 头不在其中，按需补齐。
  KINC="$KSU_DIR/kernel/kernel_includes.h"
  if [ -f "$KINC" ] && [ -f "$RESOLVER_C" ]; then
    for HDR in bsearch sort kallsyms; do
      if grep -q "ksu_lookup_kernel_symbols" "$RESOLVER_C" && ! grep -q "include <linux/$HDR.h>" "$KINC"; then
        sed -i "s|^#include <linux/kernel.h>|#include <linux/kernel.h>\n#include <linux/$HDR.h>|" "$KINC" \
          || fail "kernel_includes.h 补 <linux/$HDR.h> 失败"
        grep -q "include <linux/$HDR.h>" "$KINC" || fail "kernel_includes.h <linux/$HDR.h> 校验失败"
        echo "kernel_includes.h: 补 <linux/$HDR.h>"
      fi
    done
  fi

  # 接线 include + 处理器 + ioctl 表项（builtin dispatch.c 无 include，unity build）
  DISPATCH="$KSU_DIR/kernel/supercall/dispatch.c"
  if [ -f "$DISPATCH" ] && [ -f "$RESOLVER_C" ]; then
    if ! grep -q 'do_lookup_symbols' "$DISPATCH"; then
      echo "接线 supercall/dispatch.c: do_lookup_symbols 处理器..."
      python3 - "$DISPATCH" "$UAPI_FILE" <<'PYEOF2'
import sys, re

path = sys.argv[1]
s = open(path, encoding="utf-8", errors="surrogateescape").read()

# 1) include resolver（unity build 下放 include 源码前声明）
if '#include "infra/symbol_resolver.h"' not in s and '#include "infra/symbol_resolver.c"' not in s:
    # dispatch.c 无 include 区，用 extern 声明替代
    s = ("extern int ksu_lookup_kernel_symbols(const char *const *names, unsigned long *addrs, u32 count);\n\n" + s)

# 2) do_lookup_symbols 处理器：插在 do_disable_escape_to_root 定义前
handler = '''/*
 * Batch resolve kernel image symbols (exported or not) for userspace
 * module symbol binding, ported from SukiSU-Ultra main (UAPI 6).
 */
static int do_lookup_symbols(void __user *arg)
{
    struct ksu_lookup_symbols_cmd cmd;
    const u64 __user *unames;
    u64 __user *uaddrs;
    char **names;
    unsigned long *addrs;
    int ret = 0;
    u32 i;

    if (copy_from_user(&cmd, arg, sizeof(cmd)))
        return -EFAULT;

    if (cmd.flags) {
        pr_err("lookup_symbols: unsupported flags 0x%x\\n", cmd.flags);
        return -EINVAL;
    }
    if (!cmd.count || cmd.count > KSU_LOOKUP_SYMBOLS_MAX)
        return -EINVAL;

    names = kvcalloc(cmd.count, sizeof(*names), GFP_KERNEL);
    addrs = kvcalloc(cmd.count, sizeof(*addrs), GFP_KERNEL);
    if (!names || !addrs) {
        ret = -ENOMEM;
        goto out;
    }

    unames = (const u64 __user *)(uintptr_t)cmd.names;
    uaddrs = (u64 __user *)(uintptr_t)cmd.addrs;
    for (i = 0; i < cmd.count; i++) {
        u64 uname;
        char *name;

        if (get_user(uname, unames + i)) {
            ret = -EFAULT;
            goto out;
        }
        name = strndup_user((const char __user *)(uintptr_t)uname, KSYM_NAME_LEN);
        if (IS_ERR(name)) {
            // An overlong name cannot be a kernel symbol: report it missing.
            if (PTR_ERR(name) == -EINVAL)
                continue;
            ret = PTR_ERR(name);
            goto out;
        }
        if (!*name) {
            kfree(name);
            continue;
        }
        names[i] = name;
    }

    ret = ksu_lookup_kernel_symbols((const char *const *)names, addrs, cmd.count);
    if (ret < 0)
        goto out;

    for (i = 0; i < cmd.count; i++) {
        if (put_user((u64)addrs[i], uaddrs + i)) {
            ret = -EFAULT;
            goto out;
        }
    }

out:
    if (names) {
        for (i = 0; i < cmd.count; i++)
            kfree(names[i]);
    }
    kvfree(names);
    kvfree(addrs);
    return ret;
}

'''
anchor = "static int do_disable_escape_to_root(void __user *arg)"
if anchor not in s:
    print("::error::dispatch.c 缺少 do_disable_escape_to_root 锚点，无法插入 do_lookup_symbols")
    sys.exit(1)
s = s.replace(anchor, handler + anchor, 1)

# 3) ioctl 表项：插在 LOOKUP_SYMBOLS 可用前提下，DISABLE_ESCAPE_TO_ROOT 表项之后
entry = '''    {
        .cmd = KSU_IOCTL_LOOKUP_SYMBOLS,
        .name = "LOOKUP_SYMBOLS",
        .handler = do_lookup_symbols,
        .perm_check = only_root
    },
'''
anchor2 = re.search(r"\.cmd = KSU_IOCTL_DISABLE_ESCAPE_TO_ROOT,(?:.*\n)*?    \},\n", s)
if not anchor2:
    print("::error::dispatch.c 处理表缺少 DISABLE_ESCAPE_TO_ROOT 锚点")
    sys.exit(1)
s = s[:anchor2.end()] + entry + s[anchor2.end():]

open(path, "w", encoding="utf-8", errors="surrogateescape").write(s)
print("dispatch.c: do_lookup_symbols 处理器 + LOOKUP_SYMBOLS 表项已接线")
PYEOF2
      grep -q 'do_lookup_symbols' "$DISPATCH" || fail "dispatch.c 接线后校验失败"
    else
      echo "dispatch.c 已包含 do_lookup_symbols，跳过接线"
    fi

    # builtin 以 ksu.c unity build 编译（所有 .c 经 #include 聚合进 ksu.o），
    # resolver 源码必须 #include 进 ksu.c，否则链接报 undefined symbol。
    KSU_C="$KSU_DIR/kernel/ksu.c"
    if [ -f "$KSU_C" ] && ! grep -q '#include "infra/symbol_resolver.c"' "$KSU_C"; then
      sed -i 's|^#include "infra/event_queue.c"|#include "infra/event_queue.c"\n#include "infra/symbol_resolver.c"|' "$KSU_C" \
        || fail "ksu.c include symbol_resolver.c 失败"
      grep -q '#include "infra/symbol_resolver.c"' "$KSU_C" || fail "ksu.c symbol_resolver.c include 校验失败"
      echo "ksu.c: #include infra/symbol_resolver.c 已接入（unity build）"
    elif [ -f "$KSU_C" ]; then
      echo "ksu.c 已包含 symbol_resolver.c include，跳过"
    fi

    # 初始化接线：resolver 的函数指针表需在 kernelsu_init 中初始化
    if ! grep -q 'ksu_init_symbol_resolver' "$KSU_C" 2>/dev/null; then
      python3 - "$KSU_C" <<'PYEOF3'
import sys, re
path = sys.argv[1]
s = open(path, encoding="utf-8", errors="surrogateescape").read()
if "ksu_init_symbol_resolver();" not in s:
    anchor = "    ksu_supercalls_init();"
    if anchor in s:
        s = s.replace(anchor, anchor + "\n\n    ksu_init_symbol_resolver();", 1)
        open(path, "w", encoding="utf-8", errors="surrogateescape").write(s)
        print("ksu.c: ksu_init_symbol_resolver() 已接入 kernelsu_init")
    else:
        print("::warning::ksu.c 缺少 ksu_supercalls_init 锚点，resolver 初始化未接线（LOOKUP_SYMBOLS 将退化为未初始化 walker）")
else:
    print("ksu.c 已包含 ksu_init_symbol_resolver() 调用，跳过")
PYEOF3
    else
      echo "ksu.c 已包含 ksu_init_symbol_resolver() 调用，跳过"
    fi
  fi
else
  echo "UAPI < 6 无 LOOKUP_SYMBOLS，跳过内核侧能力注入"
fi

FINAL_UAPI=$(read_uapi "$UAPI_FILE")
[ "${FINAL_UAPI:-0}" -eq "$MAIN_UAPI" ] || fail "UAPI 号校验失败（期望 $MAIN_UAPI，实际 ${FINAL_UAPI:-未知}）"
echo "UAPI 同步完成：builtin 检出 UAPI $CUR_UAPI -> $FINAL_UAPI（官方 main $MAIN_UAPI）"
rm -f "$MAIN_FILE"
