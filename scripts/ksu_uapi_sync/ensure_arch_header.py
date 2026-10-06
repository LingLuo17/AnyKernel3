#!/usr/bin/env python3
"""Supply the missing arch.h for SukiSU builtin's ksyscall backport."""

import argparse
from pathlib import Path
import re
import sys


FALLBACK = Path(__file__).with_name("arch.h")
ARCH_INCLUDE = re.compile(r'^\s*#\s*include\s+"arch\.h"', re.MULTILINE)
MACRO_USE = re.compile(r"\b(PT_REGS_[A-Z0-9_]+|PT_REAL_REGS)\s*\(")
MACRO_DEFINITION = re.compile(r"^\s*#\s*define\s+(\w+)\b", re.MULTILINE)
COMMENTS = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)


def code(text):
    return COMMENTS.sub(" ", text)


def ensure_arch_header(kernel_su):
    kernel = kernel_su / "kernel"
    includes = kernel / "kernel_includes.h"
    if not includes.is_file():
        raise ValueError(f"缺少 SukiSU kernel_includes.h: {includes}")
    if not ARCH_INCLUDE.search(code(includes.read_text(encoding="utf-8"))):
        print("当前 SukiSU 未引用 arch.h，跳过兼容头补齐")
        return

    target = kernel / "arch.h"
    exists = target.exists()
    candidate = target if exists else FALLBACK
    data = candidate.read_bytes()
    definitions = set(MACRO_DEFINITION.findall(code(data.decode("utf-8"))))
    required = set()
    for source in kernel.rglob("*"):
        if source.suffix in (".c", ".h") and source != target:
            required.update(MACRO_USE.findall(code(source.read_text(encoding="utf-8"))))
    missing = required - definitions
    if missing:
        raise ValueError("arch.h 缺少所需寄存器宏: " + ", ".join(sorted(missing)))
    if not exists:
        # Never overwrite an upstream header, including one added concurrently.
        with target.open("xb") as output:
            output.write(data)
        print(f"已补齐 SukiSU 缺失的架构兼容头: {target}")
    else:
        print(f"上游 arch.h 已存在，保留原文件: {target}")
    print(f"架构宏完整性检查通过（{len(required)} 个被引用宏）")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kernel_su", type=Path)
    args = parser.parse_args()
    try:
        ensure_arch_header(args.kernel_su.resolve())
    except (OSError, ValueError, UnicodeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
