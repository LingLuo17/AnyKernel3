#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""builtin 分支 seccomp 过滤模式改造脚本。

背景:
  SukiSU-Nova builtin 分支在 app 启动路径 (zygote setresuid 钩子,
  kernel/hook/lsm_hook.c) 对管理器与授权应用直接调用 disable_seccomp(),
  导致管理器进程自身的 seccomp 过滤器被清除, 管理器首页
  "Seccomp 状态" 显示"未启用"。main 分支 / BakaSU 的对应实现是:
  保留过滤器 ("过滤模式"), 仅通过 seccomp action cache 放行 reboot。

处理:
  1. kernel/hook/lsm_hook.c: 6 处 disable_seccomp() 调用点改写为
     ">=5.10 保留过滤器并放行 reboot / <5.10 维持 disable_seccomp()"
     (seccomp action cache 由 GKI 5.10+ 内核 backport, 与 BakaSU 一致);
     并在文件头部补 infra/seccomp_cache.h 原型声明。
  2. 聚合编译文件 (kernel/ksu.c，上游 2026-10-19 重构后更名 kernel/ksu_main.c):
     在 infra/event_queue.c 之后聚合编译 infra/seccomp_cache.c (builtin 为单编译单元)。

所有替换严格校验命中次数, 上游代码变化时报错退出 (幂等可重入)。
用法: python3 seccomp_filter_mode.py <KernelSU 目录>
"""

import re
import sys
from pathlib import Path

# 保留过滤器时的替换块 (列 0 预处理指令, 与 BakaSU 上游写法一致)
CACHE_BLOCK = (
    "#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n"
    "        if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter) {\n"
    "            spin_lock_irq(&current->sighand->siglock);\n"
    "            ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);\n"
    "            spin_unlock_irq(&current->sighand->siglock);\n"
    "        }\n"
    "#else\n"
    "        disable_seccomp();\n"
    "#endif"
)

# (编译正则, 预期命中次数, 说明)
# SUSFS 路径: handle_zygote_setresuid / handle_zygote_next_setresuid 各 1 处管理器 + 1 处授权应用
# 非 SUSFS 路径: ksu_task_fix_setuid 各 1 处
LSM_RULES = [
    (re.compile(
        r'(if \(likely\(ksu_is_manager_appid_valid\(\)\) && unlikely\(is_uid_manager\(ruid\)\)\) \{\n)'
        r'        disable_seccomp\(\);'),
     2, "SUSFS 管理器分支"),
    (re.compile(
        r'(if \(ksu_is_allow_uid_for_current\(ruid\)\) \{\n)'
        r'        disable_seccomp\(\);'),
     2, "SUSFS 授权应用分支"),
    (re.compile(
        r'(if \(unlikely\(is_uid_manager\(new_uid\)\)\) \{\n)'
        r'        disable_seccomp\(\);'),
     1, "非 SUSFS 管理器分支"),
    (re.compile(
        r'(if \(ksu_is_allow_uid_for_current\(new_uid\)\) \{\n)'
        r'        disable_seccomp\(\);'),
     1, "非 SUSFS 授权应用分支"),
]

KSU_ANCHOR = re.compile(r'(#include "infra/event_queue\.c"\n)')


def patch_lsm(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    total = 0
    for pattern, expected, name in LSM_RULES:
        text, n = pattern.subn(lambda m: m.group(1) + CACHE_BLOCK, text)
        if n != expected:
            sys.exit(f"::error::lsm_hook.c {name} 命中 {n} 处 (预期 {expected})，"
                     f"SukiSU-Nova builtin 上游代码可能已变化，请更新补丁")
        total += n
    if '#include "infra/seccomp_cache.h"' not in text:
        text = '#include "infra/seccomp_cache.h"\n\n' + text
    path.write_text(text, encoding="utf-8")
    print(f"lsm_hook.c: 已改写 {total} 处 disable_seccomp() 调用点为过滤模式")


def patch_ksu(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if '#include "infra/seccomp_cache.c"' in text:
        print(f"{path.name}: 已包含 seccomp_cache.c 聚合编译，跳过")
        return
    text, n = KSU_ANCHOR.subn(
        lambda m: m.group(1) + '#include "infra/seccomp_cache.c"\n', text)
    if n != 1:
        sys.exit(f"::error::{path.name} 未找到 infra/event_queue.c 聚合锚点，"
                 "SukiSU-Nova builtin 上游代码可能已变化，请更新补丁")
    path.write_text(text, encoding="utf-8")
    print(f"{path.name}: 已插入 infra/seccomp_cache.c 聚合编译")


def find_aggregate(kdir: Path) -> Path | None:
    # 上游 2026-10-19 重构把 kernel/ksu.c 更名为 kernel/ksu_main.c，两者都支持
    for name in ("ksu.c", "ksu_main.c"):
        p = kdir / "kernel" / name
        if p.is_file():
            return p
    return None


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"用法: {sys.argv[0]} <KernelSU 目录>")
    kdir = Path(sys.argv[1])
    lsm = kdir / "kernel" / "hook" / "lsm_hook.c"
    ksu = find_aggregate(kdir)
    if not lsm.is_file() or ksu is None:
        sys.exit(f"::error::未找到 {lsm} 或 kernel/{{ksu,ksu_main}}.c，"
                 "SukiSU-Nova builtin 目录结构可能已变化")
    patch_lsm(lsm)
    patch_ksu(ksu)


if __name__ == "__main__":
    main()
