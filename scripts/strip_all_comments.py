#!/usr/bin/env python3
"""Remove comments from project source files."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

C_STYLE = {
    ".dart",
    ".ts",
    ".kt",
    ".kts",
    ".swift",
    ".cc",
    ".h",
    ".cpp",
    ".c",
    ".rc",
    ".xcconfig",
    ".gradle",
    ".properties",
}
SQL_EXT = {".sql"}
HASH_EXT = {".yaml", ".yml", ".py", ".sh"}
XML_EXT = {".xml", ".html", ".manifest", ".storyboard"}
PBXPROJ = {".pbxproj"}

SKIP_DIRS = {
    "build",
    ".dart_tool",
    ".git",
    "node_modules",
    ".gradle",
    "Pods",
    ".symlinks",
    "ephemeral",
}

ROOTS = [
    "lib",
    "test",
    "supabase",
    "android",
    "ios",
    "macos",
    "windows",
    "linux",
    "web",
    "scripts",
]
EXTRA_FILES = ["analysis_options.yaml", "pubspec.yaml"]


def strip_c_style(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)

    while i < n:
        ch = text[i]

        if ch in ('"', "'"):
            quote = ch
            triple = i + 2 < n and text[i : i + 3] == quote * 3
            if triple:
                end = text.find(quote * 3, i + 3)
                if end == -1:
                    out.append(text[i:])
                    break
                out.append(text[i : end + 3])
                i = end + 3
                continue
            out.append(ch)
            i += 1
            while i < n:
                c = text[i]
                if c == "\\" and i + 1 < n:
                    out.append(c)
                    out.append(text[i + 1])
                    i += 2
                    continue
                if c == quote:
                    out.append(c)
                    i += 1
                    break
                out.append(c)
                i += 1
            continue

        if text.startswith("// !$*UTF8*$!", i):
            nl = text.find("\n", i)
            if nl == -1:
                out.append(text[i:])
                break
            out.append(text[i : nl + 1])
            i = nl + 1
            continue

        if text.startswith("///", i) or text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue

        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end == -1:
                break
            i = end + 2
            if i < n and text[i] == "\n":
                out.append("\n")
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def strip_sql_comments(text: str) -> str:
    lines: list[str] = []
    in_block = False
    for line in text.splitlines(keepends=True):
        if in_block:
            if "*/" in line:
                in_block = False
                after = line.split("*/", 1)[1]
                if after.strip():
                    lines.append(after)
            continue
        if "/*" in line:
            before, _, after = line.partition("/*")
            if "*/" in after:
                after = after.split("*/", 1)[1]
                line = before + after
            else:
                in_block = True
                line = before
        stripped = line.lstrip()
        if stripped.startswith("--"):
            if line.endswith("\n"):
                lines.append("\n")
            continue
        lines.append(line)
    return "".join(lines)


def strip_hash_line_comments(text: str, keep_shebang: bool = True) -> str:
    lines: list[str] = []
    for idx, line in enumerate(text.splitlines(keepends=True)):
        stripped = line.lstrip()
        if keep_shebang and idx == 0 and stripped.startswith("#!"):
            lines.append(line)
            continue
        if stripped.startswith("#"):
            if line.endswith("\n"):
                lines.append("\n")
            continue
        lines.append(line)
    return "".join(lines)


def strip_ps1_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("<#", i):
            end = text.find("#>", i + 2)
            if end == -1:
                break
            if "\n" in text[i : end + 2]:
                out.append("\n")
            i = end + 2
            continue
        if text[i] == "\n":
            out.append("\n")
            i += 1
            continue
        line_end = text.find("\n", i)
        if line_end == -1:
            line_end = n
        line = text[i:line_end]
        stripped = line.lstrip()
        if stripped.startswith("#"):
            i = line_end
            continue
        out.append(line)
        if line_end < n:
            out.append("\n")
        i = line_end + 1 if line_end < n else line_end
    return "".join(out)


def strip_xml_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("<!--", i):
            end = text.find("-->", i + 4)
            if end == -1:
                break
            if "\n" in text[i : end + 3]:
                out.append("\n")
            i = end + 3
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def normalize(text: str, original: str) -> str:
    cleaned = "\n".join(line.rstrip() for line in text.splitlines()) + (
        "\n" if text.endswith("\n") or original.endswith("\n") else ""
    )
    while "\n\n\n" in cleaned:
        cleaned = cleaned.replace("\n\n\n", "\n\n")
    return cleaned


def clean_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    suffix = path.suffix.lower()

    if suffix in C_STYLE or suffix in PBXPROJ:
        cleaned = strip_c_style(original)
    elif suffix in SQL_EXT:
        cleaned = strip_sql_comments(original)
    elif suffix in HASH_EXT:
        cleaned = strip_hash_line_comments(original)
    elif suffix == ".properties":
        return False
    elif suffix == ".ps1":
        cleaned = strip_ps1_comments(original)
    elif suffix in XML_EXT:
        cleaned = strip_xml_comments(original)
    else:
        return False

    cleaned = normalize(cleaned, original)
    if cleaned != original:
        path.write_text(cleaned, encoding="utf-8", newline="\n")
        return True
    return False


def should_process(path: Path) -> bool:
    suffix = path.suffix.lower()
    all_ext = C_STYLE | SQL_EXT | HASH_EXT | XML_EXT | PBXPROJ | {".ps1"}
    if suffix not in all_ext:
        return False
    if suffix == ".ts" and "functions" not in path.parts:
        return False
    if suffix == ".sql" and "functions" in path.parts:
        return False
    if path.name == "strip_all_comments.py":
        return False
    return True


def iter_files() -> list[Path]:
    found: list[Path] = []
    for name in ROOTS:
        base = ROOT / name
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if any(p in SKIP_DIRS for p in path.parts):
                continue
            if should_process(path):
                found.append(path)
    for name in EXTRA_FILES:
        path = ROOT / name
        if path.exists():
            found.append(path)
    return sorted(set(found))


def main() -> int:
    changed = 0
    for path in iter_files():
        if clean_file(path):
            changed += 1
            print(path.relative_to(ROOT))
    print(f"Updated {changed} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
