#!/usr/bin/env python3
"""Add and validate KernelSU's entry in the compile-time LSM count."""

import argparse
from pathlib import Path
import re
import sys

SLOT_BLOCK = """/*
 * KernelSU registers its own LSM after all built-in LSMs have initialized.
 * Keep a free static-call slot to avoid a boot-time LSM overflow panic.
 */
#if IS_ENABLED(CONFIG_KSU)
#define KSU_ENABLED 1,
#else
#define KSU_ENABLED
#endif

"""
SLOT_BLOCK = """/*
 * KernelSU registers its own LSM after all built-in LSMs have initialized.
 * Keep a free static-call slot to avoid a boot-time LSM overflow panic.
 */
#if IS_ENABLED(CONFIG_KSU)
#define KSU_ENABLED 1,
#else
#define KSU_ENABLED
#endif

"""
SLOT = "KSU_ENABLED"
GKI_LSMS = {
    "CAPABILITIES_ENABLED",
    "SELINUX_ENABLED",
    "SAFESETID_ENABLED",
    "BPF_LSM_ENABLED",
    "LANDLOCK_ENABLED",
}
SUPPORTED_LSMS = GKI_LSMS | {
    "SMACK_ENABLED",
    "APPARMOR_ENABLED",
    "TOMOYO_ENABLED",
    "YAMA_ENABLED",
    "LOADPIN_ENABLED",
    "LOCKDOWN_ENABLED",
    "IMA_ENABLED",
    "EVM_ENABLED",
    "IPE_ENABLED",
}


def max_lsm_definition(text):
    match = re.search(r"^#define[ \t]+MAX_LSM_COUNT\b", text, re.M)
    if not match:
        raise ValueError("MAX_LSM_COUNT definition not found")
    lines = iter(text[match.start():].splitlines(keepends=True))
    definition = next(lines)
    while definition.rstrip().endswith("\\"):
        definition += next(lines)
    return definition.rstrip()


def lsm_arguments(definition):
    match = re.search(r"\bCOUNT_LSMS\s*\(", definition)
    if not match:
        raise ValueError("MAX_LSM_COUNT does not use COUNT_LSMS")
    start = match.end() - 1
    depth = 0
    for index in range(start, len(definition)):
        if definition[index] == "(":
            depth += 1
        elif definition[index] == ")":
            depth -= 1
            if depth == 0:
                arguments = definition[start + 1:index]
                names = arguments.replace("\\\n", "").split()
                if not names or any(not re.fullmatch(r"[A-Z0-9_]+", name) for name in names):
                    raise ValueError("unsupported tokens in COUNT_LSMS arguments")
                return names
    raise ValueError("COUNT_LSMS has no closing parenthesis")


def validate(text):
    names = lsm_arguments(max_lsm_definition(text))
    if names.count(SLOT) != 1:
        raise ValueError("KSU_ENABLED must occur exactly once in MAX_LSM_COUNT")
    unknown = set(names) - SUPPORTED_LSMS - {SLOT}
    if unknown:
        raise ValueError("unknown LSM macros: " + ", ".join(sorted(unknown)))
    without_slot = [name for name in names if name != SLOT]
    without_ksu = sum(name in GKI_LSMS for name in without_slot)
    with_ksu = sum(name in GKI_LSMS or name == SLOT for name in names)
    if with_ksu != without_ksu + 1 or with_ksu != 6:
        raise ValueError(f"expected GKI LSM capacity 5 to 6, got {without_ksu} to {with_ksu}")
    return with_ksu


def patch(text):
    if SLOT in text:
        raise ValueError("KSU_ENABLED already present; run --verify instead")
    definition = max_lsm_definition(text)
    names = lsm_arguments(definition)
    if len(names) < 13 or "CAPABILITIES_ENABLED" not in names:
        raise ValueError("unexpected MAX_LSM_COUNT definition")
    start = definition.index("COUNT_LSMS") + len("COUNT_LSMS")
    open_brace = definition.index("(", start)
    if "\n" in definition:
        line_end = definition.index("\n", start) + 1
    else:
        line_end = open_brace + 1
    replacement = definition[:line_end] + "\t\tKSU_ENABLED\t\t\\\n" + definition[line_end:]
    if lsm_arguments(replacement) != [SLOT] + names:
        raise ValueError("KSU_ENABLED was not inserted into COUNT_LSMS")
    return text.replace(definition, SLOT_BLOCK + replacement, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        text = args.file.read_text(encoding="utf-8", errors="surrogateescape")
        if not args.verify:
            text = patch(text)
            args.file.write_text(text, encoding="utf-8", errors="surrogateescape")
        count = validate(text)
    except (OSError, ValueError, StopIteration) as error:
        sys.exit(f"{args.file}: {error}")
    print(f"Verified {args.file}: {count} LSM slots with KernelSU")


if __name__ == "__main__":
    main()
