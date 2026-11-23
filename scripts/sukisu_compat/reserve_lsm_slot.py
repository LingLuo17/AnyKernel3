#!/usr/bin/env python3
"""Reserve LSM slots for KernelSU and external BasebandGuard hooks."""

import argparse
from pathlib import Path
import re
import sys

SLOT_BLOCK = """/*
 * These modules call security_add_hooks independently of the built-in LSMs
 * counted below. Account for their static-call table entries at compile time.
 */
#if IS_ENABLED(CONFIG_BBG)
#define BBG_ENABLED 1,
#else
#define BBG_ENABLED
#endif

#if IS_ENABLED(CONFIG_KSU)
#define KSU_ENABLED 1,
#else
#define KSU_ENABLED
#endif

"""
EXTRA_LSMS = {"BBG_ENABLED", "KSU_ENABLED"}
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
    unknown = set(names) - SUPPORTED_LSMS - EXTRA_LSMS
    if unknown:
        raise ValueError("unknown LSM macros: " + ", ".join(sorted(unknown)))
    if any(names.count(name) > 1 for name in names):
        raise ValueError("MAX_LSM_COUNT contains duplicate LSM entries")
    for name in EXTRA_LSMS | SUPPORTED_LSMS:
        if not re.search(rf"^#define\s+{name}(?:\s+1,)?\s*$", text, re.M):
            raise ValueError(f"missing compile-time definition for {name}")
    if names.count("KSU_ENABLED") != 1:
        raise ValueError("KSU_ENABLED must occur exactly once in MAX_LSM_COUNT")
    base = sum(name in GKI_LSMS for name in names)
    bbg = names.count("BBG_ENABLED")
    result = base + bbg + names.count("KSU_ENABLED")
    if result != base + bbg + 1:
        raise ValueError("KernelSU did not increase MAX_LSM_COUNT by one")
    return base, bbg, result


def patch(text):
    if any(name in text for name in EXTRA_LSMS):
        raise ValueError("external LSM slot already present; run --verify instead")
    definition = max_lsm_definition(text)
    names = lsm_arguments(definition)
    if len(names) < 13:
        raise ValueError("unexpected MAX_LSM_COUNT definition")
    start = definition.index("COUNT_LSMS") + len("COUNT_LSMS")
    open_brace = definition.index("(", start)
    if "\n" in definition:
        line_end = definition.index("\n", start) + 1
    else:
        line_end = open_brace + 1
    slots = "\t\tBBG_ENABLED\t\t\\\n\t\tKSU_ENABLED\t\t\\\n"
    replacement = definition[:line_end] + slots + definition[line_end:]
    if lsm_arguments(replacement) != ["BBG_ENABLED", "KSU_ENABLED"] + names:
        raise ValueError("external LSM slots were not inserted into COUNT_LSMS")
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
        base, bbg, count = validate(text)
    except (OSError, ValueError, StopIteration) as error:
        sys.exit(f"{args.file}: {error}")
    print(f"Verified {args.file}: {base} base + {bbg} BBG + 1 KSU = {count} LSM slots")


if __name__ == "__main__":
    main()
