#!/usr/bin/env python3
"""Regression checks for the missing SukiSU architecture header."""

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SCRIPT = HERE / "ensure_arch_header.py"
VERSION = "#define KERNEL_VERSION(a,b,c) (((a)<<16)|((b)<<8)|(c))\n#define LINUX_VERSION_CODE KERNEL_VERSION(6,1,138)\n"
STRUCTS = {
    "aarch64-linux-gnu": "struct pt_regs { unsigned long regs[31], sp, pc; };",
    "arm-linux-gnueabi": "struct pt_regs { unsigned long uregs[18]; };",
    "x86_64-linux-gnu": "struct pt_regs { unsigned long di, si, dx, r10, cx, r8, r9, sp, bp, ax, ip; };",
}
SMOKE = """
#include "arch.h"
_Static_assert(sizeof(SYS_EXECVE_SYMBOL) > 1, "execve symbol missing");
_Static_assert(sizeof(SYS_REBOOT_SYMBOL) > 1, "reboot symbol missing");
void assign(struct pt_regs *p) {
    PT_REGS_PARM1(p) = 1;
    PT_REGS_PARM2(p) = 2;
    PT_REGS_PARM3(p) = 3;
    PT_REGS_SYSCALL_PARM4(p) = 4;
    PT_REGS_CCALL_PARM4(p) = 4;
    PT_REGS_PARM5(p) = 5;
    PT_REGS_PARM6(p) = 6;
    PT_REGS_RET(p) = 7;
    PT_REGS_FP(p) = 8;
    PT_REGS_RC(p) = 9;
    PT_REGS_SP(p) = 10;
    PT_REGS_IP(p) = 11;
}
struct pt_regs *unwrap(struct pt_regs *p) { return PT_REAL_REGS(p); }
"""


class ArchHeaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sukisu-arch-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.kernel_su = self.root / "KernelSU"
        self.kernel = self.kernel_su / "kernel"
        self.kernel.mkdir(parents=True)
        self.includes = self.kernel / "kernel_includes.h"
        self.includes.write_text('#include "arch.h"\n', encoding="utf-8")
        (self.kernel / "compat.h").write_text(
            "void f(void) { PT_REGS_PARM1(p) = 1; PT_REGS_SYSCALL_PARM4(p) = 4; }\n",
            encoding="utf-8",
        )

    def run_sync(self):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.kernel_su)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )

    def test_missing_header_is_supplied_and_repeated_run_is_noop(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        target = self.kernel / "arch.h"
        self.assertEqual(target.read_bytes(), (HERE / "arch.h").read_bytes())
        before = target.read_bytes()
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, target.read_bytes())

    def test_upstream_header_is_not_overwritten(self):
        target = self.kernel / "arch.h"
        original = b"// upstream header\n#define PT_REGS_PARM1(p) upstream(p)\n#define PT_REGS_SYSCALL_PARM4(p) fourth(p)\n"
        target.write_bytes(original)
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(target.read_bytes(), original)

    def test_old_source_without_include_is_unchanged(self):
        self.includes.write_text('// #include "arch.h"\n', encoding="utf-8")
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.kernel / "arch.h").exists())

    def test_unknown_required_macro_fails_without_creating_header(self):
        (self.kernel / "compat.h").write_text("PT_REGS_NEW_UNKNOWN(p);\n", encoding="utf-8")
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PT_REGS_NEW_UNKNOWN", result.stderr)
        self.assertFalse((self.kernel / "arch.h").exists())

    def test_incomplete_upstream_header_fails_without_overwrite(self):
        target = self.kernel / "arch.h"
        target.write_bytes(b"// upstream incomplete\n")
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), b"// upstream incomplete\n")

    def test_shared_workflow_invokes_guard_before_uapi(self):
        lines = (REPO / ".github/workflows/build.yml").read_text(encoding="utf-8").splitlines()
        start = lines.index("      - name: 补齐 SukiSU 架构兼容头文件")
        self.assertLess(start, lines.index("      - name: 同步 SukiSU 内核 UAPI 版本（对齐官方管理器）"))
        self.assertEqual(lines[start + 1].strip(), "if: inputs.ksu_variant == 'SukiSU'")
        command = lines[start + 4].strip()
        if os.name == "nt":
            command = re.sub(r"\bpython3\b", shlex.quote(Path(sys.executable).as_posix()), command)
        env = os.environ.copy()
        env["GITHUB_WORKSPACE"] = REPO.as_posix()
        result = subprocess.run([shutil.which("bash"), "-e", "-c", command], cwd=self.root,
                                env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.kernel / "arch.h").is_file())

    @unittest.skipUnless(shutil.which("clang"), "clang is required for architecture syntax checks")
    def test_register_macros_compile_on_supported_architectures(self):
        linux = self.root / "linux"
        linux.mkdir()
        (linux / "version.h").write_text(VERSION, encoding="utf-8")
        for arch, structure in STRUCTS.items():
            with self.subTest(arch=arch):
                source = self.root / "smoke.c"
                source.write_text(structure + "\n" + SMOKE, encoding="utf-8")
                result = subprocess.run(
                    [shutil.which("clang"), "--target=" + arch, "-std=gnu11", "-Werror",
                     "-fsyntax-only", "-I", str(self.root), "-I", str(HERE), str(source)],
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
