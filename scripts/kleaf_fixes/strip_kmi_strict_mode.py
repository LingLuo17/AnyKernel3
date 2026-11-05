#!/usr/bin/env python3
"""从 common/BUILD.bazel 完整移除 kmi_symbol_list_strict_mode。

GKI 各分支里该属性有三种形态：
  * 单行规则属性      kmi_symbol_list_strict_mode = True/False,
  * target_configs 字典条目 "kmi_symbol_list_strict_mode": True/False,
  * 多行 select({...}) 块（android17-6.18，按 page_size 条件取值）

原先的 `sed '/kmi_symbol_list_strict_mode/d'` 只会删掉 select 块的首行，
残留孤儿字典字面量导致 BUILD.bazel 语法错误（bazel 解析失败，包内所有
目标不可见）。这里按形态匹配，整个属性/条目/块一起移除。
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: %s BUILD.bazel" % sys.argv[0], file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        src = f.read()

    total = src.count("kmi_symbol_list_strict_mode")

    # 单行规则属性（kernel_build/common_kernel 调用）
    src = re.sub(
        r"^[ \t]*kmi_symbol_list_strict_mode[ \t]*=[ \t]*(?:True|False),[ \t]*\n",
        "",
        src,
        flags=re.M,
    )
    # target_configs 字典条目
    src = re.sub(
        r'^[ \t]*"kmi_symbol_list_strict_mode"[ \t]*:[ \t]*(?:True|False),[ \t]*\n',
        "",
        src,
        flags=re.M,
    )
    # 多行 select({...}) 块：字典体只有平铺的 "label": value 行，
    # 首个 "}),  即块结尾
    src = re.sub(
        r"^[ \t]*kmi_symbol_list_strict_mode[ \t]*=[ \t]*select\(\{.*?\}\),[ \t]*\n",
        "",
        src,
        flags=re.M | re.S,
    )

    removed = total - src.count("kmi_symbol_list_strict_mode")
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    print("BUILD.bazel: 已移除 %d 处 kmi_symbol_list_strict_mode" % removed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
