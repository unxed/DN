#!/usr/bin/env python3
"""List Pascal routines nested two or more levels deep in dn/src; with --reads, only those using a name declared above their parent."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

TOKEN = re.compile(r"[A-Za-z_][A-Za-z_0-9]*|[=.;:,()]")
OPENERS = {"begin", "asm", "case", "try", "record", "object", "class"}
ROUTINE_WORDS = {"procedure", "function", "constructor", "destructor"}
SECTION_WORDS = {"var", "const", "type", "label", "threadvar", "resourcestring"}
KEYWORDS = OPENERS | ROUTINE_WORDS | SECTION_WORDS | {
    "end", "if", "then", "else", "while", "do", "for", "to", "downto", "repeat", "until", "of", "with",
    "and", "or", "xor", "not", "div", "mod", "shl", "shr", "in", "is", "as", "nil", "true", "false",
    "exit", "break", "continue", "finally", "except", "on", "out", "array", "set", "string", "inherited",
    "absolute", "packed", "forward", "external", "interface", "implementation", "uses", "goto",
}


@dataclass
class Routine:
    name: str
    line: int
    body_started: bool = False
    is_function: bool = False
    declared: set = field(default_factory=set)  # parameters and `var` names, lower case
    used: set = field(default_factory=set)  # identifiers met in the body
    section: str = ""  # `var`/`const`/... while its declarations are read
    mode: str = ""  # "names" or "skip" inside a declaration section or a parameter list
    skip_depth: int = 0


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


def track_declarations(routine: Routine, word: str, previous: str, block_depth: int) -> bool:
    """Collect what `routine` declares (parameters, `var` names) and, in its body, uses.

    Returns True when the token was consumed as a declaration; routine words, `begin` and the other
    structural tokens are left to the caller.
    """
    identifier = word[0].isalpha() or word[0] == "_"
    if routine.body_started:
        if identifier and word not in KEYWORDS and previous != ".":
            routine.used.add(word)
        return False
    if routine.section == "header":
        if word == "(":
            routine.section, routine.mode, routine.skip_depth = "params", "names", 1
        elif word == ";":
            routine.section = ""
        return word in {"(", ";"}
    if routine.section == "params":
        if word == "(":
            routine.skip_depth += 1
        elif word == ")":
            routine.skip_depth -= 1
            if routine.skip_depth == 0:
                routine.section = "header"
                return True
        elif routine.mode == "names":
            if word == ":":
                routine.mode = "skip"
            elif identifier and word not in KEYWORDS:
                routine.declared.add(word)
        elif word == ";" and routine.skip_depth == 1:
            routine.mode = "names"
        return True
    if word in ROUTINE_WORDS or word in {"begin", "asm"}:
        return False
    if word in SECTION_WORDS and previous == ";":
        routine.section, routine.mode, routine.skip_depth = word, "names", 0
        return True
    if routine.section != "var":
        return False
    if routine.mode == "names":
        if word == ":":
            routine.mode, routine.skip_depth = "skip", block_depth
        elif identifier and word not in KEYWORDS:
            routine.declared.add(word)
        return True
    if word == ";" and block_depth == routine.skip_depth:
        routine.mode = "names"
    return False


def reads_above_parent(routines: list[Routine], index: int) -> list[str]:
    """Names the body of routines[index] takes from routines[:index - 1], skipping its parent and itself."""
    reads = []
    for name in sorted(routines[index].used):
        for scope in range(index, -1, -1):
            if name in routines[scope].declared:
                if scope <= index - 2:
                    reads.append(f"{name} ({routines[scope].name})")
                break
    return reads


def scan(path: Path) -> list[tuple[int, str, str, list[str]]]:
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
    found: list[tuple[int, str, str, list[str]]] = []
    i = 0
    while i < len(tokens):
        word, number = tokens[i]
        previous = tokens[i - 1][0] if i else ""
        following = tokens[i + 1][0] if i + 1 < len(tokens) else ""
        if routines and track_declarations(routines[-1], word, previous, len(blocks)):
            i += 1
            continue
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
            routine = Routine(name, number, section="header")
            if word == "function":
                routine.is_function = True
                routine.declared.update({name.rsplit(".", 1)[-1], "result"})
            routines.append(routine)
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
                    if index >= 2:
                        found.append((owner.line, routines[index - 1].name, owner.name, reads_above_parent(routines, index)))
                    del routines[index:]
        i += 1
    # An unbalanced file means the scan lost its place and the list would be silently incomplete.
    found.sort(key=lambda entry: entry[0])
    if blocks or routines:
        raise ValueError(f"{path}: unbalanced begin/end after line {tokens[-1][1] if tokens else 0}")
    return found


def main() -> int:
    arguments = [argument for argument in sys.argv[1:] if argument != "--reads"]
    only_reads = len(arguments) != len(sys.argv) - 1
    root = Path(arguments[0]) if arguments else Path("dn/src")
    files = sorted(root.rglob("*.pas")) if root.is_dir() else [root]
    findings: list[tuple[Path, int, str, str, list[str]]] = []
    for path in files:
        try:
            scanned = scan(path)
        except ValueError as error:
            print(error, file=sys.stderr)
            return 2
        for line, parent, child, reads in scanned:
            findings.append((path, line, parent, child, reads))
    if only_reads:
        # Only routines two or more levels deep that use a name declared above their parent.
        findings = [finding for finding in findings if finding[4]]
    for path, line, parent, child, reads in findings:
        suffix = f" reads {', '.join(reads)}" if only_reads else ""
        print(f"{path}:{line}: {child} nested in {parent}{suffix}")
    if not findings:
        print("No nested routines found." if not only_reads else "No routines reading above their parent found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
