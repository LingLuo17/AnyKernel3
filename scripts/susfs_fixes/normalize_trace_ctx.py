#!/usr/bin/env python3
# 归一化 SUSFS 主补丁中「插入 susfs_def.h」hunk 的 trace/hooks 上下文
#
# 背景：
#   SUSFS 上游 2026-10-18 把 gki-android13-5.15 主补丁 rebase 到 5.15.211，
#   fs/proc/task_mmu.c 与 fs/namespace.c 的首个 hunk 变为以
#   `#include <trace/hooks/mm.h>` / `#include <trace/hooks/blk.h>` 作为上下文。
#   - 5.15.74~194 的 GKI 源码没有这两行，hunk 整段被拒 ->
#     susfs_def.h 未引入 -> SUSFS_IS_INODE_* 隐式声明 -> clang -Werror 中断编译；
#   - 5.15.220(LTS) 原生含这两行，旧脚本却为匹配 rebase 前的补丁把它们删掉，
#     同样导致整段被拒。
#
# 策略：
#   只处理「补丁体中出现 susfs_def.h」的 hunk；若该 hunk 的 trace/hooks 上下文行
#   在目标文件头部不存在，就把这行从补丁副本中剔除并重算 hunk 行数。源码本身
#   不做任何增删。目标文件已有该行时保持补丁原样。
import re
import sys

HUNK_HDR = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
TRACE_PREFIX = '#include <trace/hooks/'
HEAD_LIMIT = 200


def read_head(path):
    """返回目标文件前 HEAD_LIMIT 行的去空白内容，文件不存在时返回 None。"""
    try:
        with open(path, encoding='utf-8', errors='surrogateescape') as f:
            head = []
            for _ in range(HEAD_LIMIT):
                line = f.readline()
                if not line:
                    break
                head.append(line.strip())
            return head
    except OSError:
        return None


def normalize(patch_path):
    with open(patch_path, encoding='utf-8', errors='surrogateescape') as f:
        lines = f.read().splitlines()

    out = []
    touched = set()
    dropped = 0
    cur_file = None
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('+++ b/'):
            cur_file = line[6:].split('\t')[0].strip()
            out.append(line)
            i += 1
            continue

        m = HUNK_HDR.match(line)
        if not m:
            out.append(line)
            i += 1
            continue

        j = i + 1
        body = []
        while j < len(lines) and not lines[j].startswith(('@@', 'diff --git')):
            body.append(lines[j])
            j += 1

        if cur_file and any('susfs_def.h' in l for l in body):
            head = read_head(cur_file)
            if head is not None:
                kept = []
                for l in body:
                    ctx = l[1:].strip()
                    if l[:1] == ' ' and ctx.startswith(TRACE_PREFIX) and ctx not in head:
                        dropped += 1
                        continue
                    kept.append(l)
                if len(kept) != len(body):
                    old_count = sum(1 for l in kept if l[:1] in (' ', '-'))
                    new_count = sum(1 for l in kept if l[:1] in (' ', '+'))
                    line = '@@ -%s,%d +%s,%d @@' % (m.group(1), old_count, m.group(3), new_count)
                    body = kept
                    touched.add(cur_file)

        out.append(line)
        out.extend(body)
        i = j

    if dropped:
        with open(patch_path, 'w', encoding='utf-8', errors='surrogateescape', newline='\n') as f:
            f.write('\n'.join(out) + '\n')
        print('SUSFS 补丁上下文已归一化：%s 移除 %d 行缺失的 trace/hooks 上下文'
              % (', '.join(sorted(touched)), dropped))
    else:
        print('SUSFS 头文件上下文无需归一化')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('用法: normalize_trace_ctx.py <patch>', file=sys.stderr)
        sys.exit(2)
    normalize(sys.argv[1])
