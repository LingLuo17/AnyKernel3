#!/usr/bin/env python3
"""Regression tests for external LSM static-call capacity."""

from pathlib import Path
import tempfile
import unittest

from reserve_lsm_slot import (
    EXTRA_LSMS,
    GKI_LSMS,
    SUPPORTED_LSMS,
    lsm_arguments,
    max_lsm_definition,
    patch,
    validate,
)


class ExternalSlotTest(unittest.TestCase):
    def setUp(self):
        self.upstream = "\n".join(
            [
                f"#if IS_ENABLED(CONFIG_{name.removesuffix('_ENABLED')})\n"
                f"#define {name} 1,\n#else\n#define {name}\n#endif"
                for name in SUPPORTED_LSMS
            ]
            + [f"#define MAX_LSM_COUNT COUNT_LSMS( \\\n\t{' \\\n\t'.join(sorted(SUPPORTED_LSMS))})"]
        )

    def test_bbg_and_ksu_get_distinct_slots(self):
        names = lsm_arguments(max_lsm_definition(patch(self.upstream)))
        enabled = set(names) - EXTRA_LSMS
        base = sum(name in GKI_LSMS for name in enabled)
        for bbg in (False, True):
            capacity = base + int(bbg) + 1
            self.assertEqual(capacity, base + int("BBG_ENABLED" in names and bbg) + 1)
            self.assertEqual(capacity, 7 if bbg else 6)

    def test_real_android_shape_and_idempotency(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lsm_count.h"
            path.write_text(self.upstream, encoding="utf-8")
            patched = patch(self.upstream)
            self.assertEqual(validate(patched), (5, 1, 7))
            path.write_text(patched, encoding="utf-8")
            self.assertRaises(ValueError, patch, patched)
            without_bbg = patched.replace("BBG_ENABLED\t\t\\\n", "")
            self.assertEqual(validate(without_bbg), (5, 0, 6))


if __name__ == "__main__":
    unittest.main()
