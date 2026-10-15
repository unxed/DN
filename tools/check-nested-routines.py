#!/usr/bin/env python3
"""List Pascal routines nested inside another routine in dn/src."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

TOKEN = re.compile(r"[A-Za-z_][A-Za-z_0-9]*|[=.;]")
OPENERS = {"begin", "case", "try", "record", "object", "class"}


@dataclass
class Routine:
    name: str
    line: int
    body_started: bool = False


def code_lines(text: str) -> list[str]:
    """Remove comments and strings while preserving source line numbers."""
    result: list[str] = []
    state = "code"
    i = 0
    line: list[str] = []
    while i < len(text):
        char = text[i]
        following = text[i + 1] if i + 1 < len(text) else ""
        if char == "\n":
            result.append("".join(line))
            line = []
            if state == "line-comment":
                state = "code"
            i += 1
            continue
        if state == "code":
            if char == "/" and following == "/":
                state = "line-comment"
                line.extend("  ")
                i += 2
                continue
            if char == "{" or (char == "(" and following == "*"):
                state = "brace-comment" if char == "{" else "paren-comment"
                line.extend("  ")
                i += 1 if char == "{" else 2
                continue
            if char == "'":
                state = "string"
                line.append(" ")
            else:
                line.append(char)
        elif state == "line-comment":
            line.append(" ")
        elif state == "brace-comment":
            if char == "}":
                state = "code"
            line.append(" ")
        elif state == "paren-comment":
            if char == "*" and following == ")":
                state = "code"
                line.extend("  ")
                i += 2
                continue
            line.append(" ")
        else:  # Pascal strings escape a quote by doubling it.
            if char == "'" and following == "'":
                line.extend("  ")
                i += 2
                continue
            if char == "'":
                state = "code"
            line.append(" ")
        i += 1
    if line:
        result.append("".join(line))
    return result


def scan(path: Path) -> list[tuple[int, str, str]]:
    lines = code_lines(path.read_text(encoding="latin-1"))
    tokens: list[tuple[str, int]] = []
    in_implementation = False
    for number, text in enumerate(lines, 1):
        for match in TOKEN.finditer(text):
            value = match.group(0)
            lower = value.lower()
            if lower == "implementation":
                in_implementation = True
            if in_implementation:
                tokens.append((lower, number))

    routines: list[Routine] = []
    # Each opener stores the routine whose body begins at that `begin`, if any.
    blocks: list[tuple[str, Routine | None]] = []
    found: list[tuple[int, str, str]] = []
    i = 0
    while i < len(tokens):
        word, number = tokens[i]
        if word in {"procedure", "function"}:
            # Procedural types and class declarations are not routine bodies.
            previous = tokens[i - 1][0] if i else ""
            in_class = any(block == "class" for block, _ in blocks)
            if previous == "=" or in_class:
                i += 1
                continue
            # Skip class method implementations; their qualified name contains a dot.
            name_parts: list[str] = []
            j = i + 1
            while j < len(tokens) and tokens[j][0] not in {";", "."}:
                if tokens[j][0] in {"begin", "end"}:
                    break
                name_parts.append(tokens[j][0])
                if len(name_parts) == 1 and j + 1 < len(tokens) and tokens[j + 1][0] == ".":
                    name_parts.append(".")
                    j += 1
                    break
                j += 1
            if name_parts and "." not in name_parts:
                name = name_parts[0]
                if len(routines) >= 2:
                    found.append((number, routines[-1].name, name))
                routines.append(Routine(name, number))
        elif word in OPENERS:
            owner = None
            if word == "begin":
                for routine in reversed(routines):
                    if not routine.body_started:
                        routine.body_started = True
                        owner = routine
                        break
            blocks.append((word, owner))
        elif word == "end":
            if blocks:
                _, owner = blocks.pop()
                if owner is not None and owner in routines:
                    index = routines.index(owner)
                    del routines[index:]
        i += 1
    return found


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dn/src")
    files = sorted(root.rglob("*.pas")) if root.is_dir() else [root]
    findings: list[tuple[Path, int, str, str]] = []
    for path in files:
        for line, parent, child in scan(path):
            findings.append((path, line, parent, child))
    for path, line, parent, child in findings:
        print(f"{path}:{line}: {child} nested in {parent}")
    if not findings:
        print("No nested routines found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
