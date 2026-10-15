#!/usr/bin/env python3
"""List Pascal routines nested inside another routine in dn/src."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

TOKEN = re.compile(r"[A-Za-z_][A-Za-z_0-9]*|[=.;]")
OPENERS = {"begin", "asm", "case", "try", "record", "object", "class"}
ROUTINE_WORDS = {"procedure", "function", "constructor", "destructor"}


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
    # A program or library has no `implementation`: all of it is code.
    in_implementation = not any(re.match(r"\s*implementation\b", text, re.I) for text in lines)
    for number, text in enumerate(lines, 1):
        for match in TOKEN.finditer(text):
            value = match.group(0)
            lower = value.lower()
            if lower == "implementation":
                in_implementation = True
            if in_implementation:
                tokens.append((lower, number))

    routines: list[Routine] = []
    # Each opener stores the routine whose body begins at that `begin`/`asm`, if any.
    blocks: list[tuple[str, Routine | None]] = []
    found: list[tuple[int, str, str]] = []
    i = 0
    while i < len(tokens):
        word, number = tokens[i]
        previous = tokens[i - 1][0] if i else ""
        following = tokens[i + 1][0] if i + 1 < len(tokens) else ""
        if word in ROUTINE_WORDS:
            # Procedural types (`= procedure`, `: procedure`) and class declarations are not routine bodies.
            if previous in {"=", ":"} or any(block == "class" for block, _ in blocks):
                i += 1
                continue
            # The name is `Name` or `Class.Name`.
            name = following
            if i + 3 < len(tokens) and tokens[i + 2][0] == ".":
                name = f"{following}.{tokens[i + 3][0]}"
            if name in {"", ";", "(", "="}:
                i += 1
                continue
            if len(routines) >= 2:
                found.append((number, routines[-1].name, name))
            routines.append(Routine(name, number))
        elif word in {"forward", "external"}:
            # A declaration without a body.
            if routines and not routines[-1].body_started:
                routines.pop()
        elif word == "class" and following in ROUTINE_WORDS:
            pass  # `class function`: the routine itself is handled by the next token
        elif word in {"class", "object"} and (previous != "=" or following in {"of", ";"}):
            pass  # `class of`, a forward `= class;`, a `class` modifier: no `end` follows
        elif word == "case" and blocks and blocks[-1][0] == "record":
            pass  # the variant part of a record shares the `end` of the record
        elif word in OPENERS:
            owner = None
            # Only the innermost routine can start its body here; a `begin` inside a started body is a block.
            if word in {"begin", "asm"} and routines and not routines[-1].body_started:
                routines[-1].body_started = True
                owner = routines[-1]
            blocks.append((word, owner))
        elif word == "end":
            if blocks:
                _, owner = blocks.pop()
                if owner is not None and owner in routines:
                    index = routines.index(owner)
                    del routines[index:]
        i += 1
    # An unbalanced file means the scan lost its place and the list would be silently incomplete.
    if blocks or routines:
        raise ValueError(f"{path}: unbalanced begin/end after line {tokens[-1][1] if tokens else 0}")
    return found


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dn/src")
    files = sorted(root.rglob("*.pas")) if root.is_dir() else [root]
    findings: list[tuple[Path, int, str, str]] = []
    for path in files:
        try:
            scanned = scan(path)
        except ValueError as error:
            print(error, file=sys.stderr)
            return 2
        for line, parent, child in scanned:
            findings.append((path, line, parent, child))
    for path, line, parent, child in findings:
        print(f"{path}:{line}: {child} nested in {parent}")
    if not findings:
        print("No nested routines found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
