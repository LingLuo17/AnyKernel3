#!/usr/bin/env python3
import pathlib
import re
import sys

API = "https://git.zako.shirkneko.top:20004/api/v1/repos/$(REPO_OWNER)/$(REPO_NAME)"
replacements = {
    "REPO_OWNER": "REPO_OWNER  := shirkneko",
    "REPO_NAME": "REPO_NAME   := SukiSU",
    "VERSION_OFFSET": "VERSION_OFFSET  := 996",
    "GITHUB_API_BASE": f"RELEASE_API_BASE := {API}",
    "GITHUB_COMMITS": (
        'RELEASE_COMMITS  := $(shell $(CURL_BIN) -s -D - -o /dev/null '
        '"$(RELEASE_API_BASE)/commits?sha=$(REPO_BRANCH)&limit=1" 2>/dev/null '
        "| tr -d '\\r' | sed -n 's/^[Xx]-[Tt]otal-[Cc]ount:[[:space:]]*\\([0-9]*\\).*/\\1/p')"
    ),
    "LOCAL_COUNT": "LOCAL_COUNT     := $(if $(RELEASE_COMMITS),$(RELEASE_COMMITS),$(git_commit_count))",
    "KSU_VERSION": (
        "KSU_VERSION     := $(if $(LOCAL_COUNT),"
        "$(shell expr $(VERSION_BASE) + $(LOCAL_COUNT) + $(VERSION_OFFSET)),$(VERSION_BASE))"
    ),
    "KSU_GITHUB_VER": (
        'KSU_RELEASE_VER  := $(shell $(CURL_BIN) -s "$(RELEASE_API_BASE)/releases/latest" '
        "2>/dev/null | grep -o '\"tag_name\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4 | sed 's/^v//')"
    ),
    "VERSION_TAG": "VERSION_TAG     := $(or $(KSU_RELEASE_VER),$(git_latest_tag),3.0.0)",
}

path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "KernelSU/kernel/Makefile")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
for key, replacement in replacements.items():
    pattern = re.compile(rf"^{key}\s*:=.*$")
    matched = False
    for index, line in enumerate(lines):
        if pattern.match(line.rstrip("\r\n")):
            ending = "\r\n" if line.endswith("\r\n") else "\n"
            lines[index] = replacement + ending
            matched = True
            break
    if not matched:
        sys.exit(f"missing {key} in {path}")

path.write_text("".join(lines), encoding="utf-8", newline="")
