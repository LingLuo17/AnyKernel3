#!/usr/bin/env bash
# 修复 Baseband-guard blkdev_helper.c 在 Linux 6.9+ 上的编译失败
#
# 背景：上游 commit 1c66495 引入的 is_allowed_partition_dev_resolve() 调用
# blkdev_get_no_open()/blkdev_put_no_open()，并只 include <linux/blkdev.h>。
# 该 API 在 5.11~6.8 声明于 include/linux/blkdev.h（单参 blkdev_get_no_open(dev)），
# 6.9 起移入内核私有头 block/blk.h，且 6.15 起签名变为双参
# blkdev_get_no_open(dev, bool autoload)。在 6.9+ 上编译时声明不可见，
# clang -Werror 报 implicit function declaration + int→指针转换错误。
# （上游 CI main 分支在 android17-6.18 同样失败，尚无修复；baseband_guard.c /
# tracing.c 因 include kernel_compat.h（内部已 include "blk.h"）不受影响。）
#
# 修复：按内核头文件实际内容检测——声明已移入 block/blk.h 时补
# #include "blk.h"（BBG Makefile 已带 -I$(srctree)/block）并将调用改为
# 头文件中实际存在的形态；声明仍在公共头（<=6.8 及回移分支）则不改动。
#
# 用法：fix_blkdev_helper.sh <内核源码根>（如 common/；默认 common/）
set -eo pipefail

KERNEL_SRC="${1:-common}"
BBG_C="$KERNEL_SRC/security/baseband-guard/blkdev_helper.c"

if [ ! -f "$BBG_C" ]; then
  echo "::warning::BBG blkdev_helper.c 不存在（$BBG_C），跳过补丁"
  exit 0
fi

if ! grep -q 'blkdev_get_no_open' "$BBG_C"; then
  echo "BBG blkdev_helper.c 无需补丁（无 blkdev_get_no_open 调用）"
  exit 0
fi

if grep -q 'BBG_BLKDEV_COMPAT_DONE' "$BBG_C"; then
  echo "BBG blkdev_helper.c 已打过补丁，跳过"
  exit 0
fi

# 声明仍在公共头 include/linux/blkdev.h（<=6.8 及部分回移分支）：无需修改
if grep -q 'blkdev_get_no_open' "$KERNEL_SRC/include/linux/blkdev.h" 2>/dev/null; then
  echo "BBG blkdev_helper.c 无需补丁（blkdev_get_no_open 声明在公共头）"
  exit 0
fi

# 6.9+：声明移入内核私有头 block/blk.h；6.15+ 签名带 bool autoload
if grep -q 'blkdev_get_no_open(dev_t dev, bool' "$KERNEL_SRC/block/blk.h" 2>/dev/null; then
  NEW_CALL='bdev = blkdev_get_no_open(dev, true);'
elif grep -q 'blkdev_get_no_open(dev_t dev)' "$KERNEL_SRC/block/blk.h" 2>/dev/null; then
  NEW_CALL='bdev = blkdev_get_no_open(dev);'
else
  echo "::warning::block/blk.h 中无 blkdev_get_no_open 声明，跳过自动适配（上游 BBG 布局可能已变化）"
  exit 0
fi

echo "BBG: blkdev_get_no_open 声明位于 block/blk.h，补 include 并适配调用形态"

if ! grep -q '#include "blk.h"' "$BBG_C"; then
  sed -i 's|#include <linux/blkdev.h>|#include <linux/blkdev.h>\n#include "blk.h"|' "$BBG_C"
fi
sed -i "s|bdev = blkdev_get_no_open(dev);|$NEW_CALL|" "$BBG_C"
sed -i '1i /* BBG_BLKDEV_COMPAT_DONE */' "$BBG_C"

echo "BBG blkdev_helper.c 兼容补丁完成"
