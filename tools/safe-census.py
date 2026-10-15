#!/usr/bin/env python3
"""Count Safe Pascal rules S1-S4 and S9 in the DN and TV source trees."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ("dn/src", "dn/compat", "tv/src")
RULES = {
    "S1": re.compile(r"\b(?:GetMem|FreeMem|ReallocMem|AllocMem|New|Dispose)\s*\(", re.I),
    "S2": re.compile(r"\b(?:Move|FillChar)\s*\(", re.I),
    "S3": re.compile(r"\.\s*(?:Free|Destroy)\b|\bFreeAndNil\s*\(", re.I),
    "S4": re.compile(
        r"\b(?:Pointer|PByte|PChar|PAnsiChar|PWideChar)\b|\^\s*[A-Za-z_]"
        r"|@\s*(?:[A-Za-z_]|\()",
        re.I,
    ),
    "S9": re.compile(r"\b(?:UnicodeString|WideString|ShortString)\b|\bString\s*\[\s*\d+\s*\]", re.I),
}
COMMENTS = re.compile(r"//[^\n]*|\{[^}]*\}|\(\*.*?\*\)", re.S)
STRINGS = re.compile(r"'(?:[^']|'')*'")
OBJECT_DECL = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?object\b", re.I | re.M)
CLASS_DECL = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?class\b", re.I | re.M)


def code_only(text):
    """Return Pascal code with comments and string literals blanked out."""
    text = COMMENTS.sub(lambda match: re.sub(r"[^\n]", " ", match.group()), text)
    return STRINGS.sub(lambda match: re.sub(r"[^\n]", " ", match.group()), text)


def source_files(root=ROOT):
    for directory in SOURCE_DIRS:
        path = root / directory
        if not path.is_dir():
            raise FileNotFoundError("source directory is missing: %s" % directory)
        yield from sorted(
            file for file in path.rglob("*")
            if file.is_file() and file.suffix.lower() in {".pas", ".pp", ".inc"}
        )


def count_file(path, root=ROOT):
    code = code_only(path.read_text(encoding="utf-8"))
    counts = {rule: len(pattern.findall(code)) for rule, pattern in RULES.items()}
    counts["objects"] = len(set(OBJECT_DECL.findall(code)))
    counts["classes"] = len(set(CLASS_DECL.findall(code)))
    counts["file"] = path.relative_to(root).as_posix()
    return counts


def census(root=ROOT):
    units = [count_file(path, root) for path in source_files(root)]
    totals = {key: sum(unit[key] for unit in units) for key in (*RULES, "objects", "classes")}
    totals["units"] = len(units)
    closest = sorted(
        (unit for unit in units if unit["objects"] == 0),
        key=lambda unit: (sum(unit[rule] for rule in RULES), -unit["classes"], unit["file"]),
    )[:10]
    return {"units": units, "totals": totals, "closest_to_safe": closest}


def render(report):
    columns = (*RULES, "objects", "classes")
    print("file\t" + "\t".join(columns))
    for unit in report["units"]:
        print(unit["file"] + "\t" + "\t".join(str(unit[key]) for key in columns))
    totals = report["totals"]
    print("TOTAL\t" + "\t".join(str(totals[key]) for key in columns))
    print("object/class declarations: %d/%d" % (totals["objects"], totals["classes"]))
    print("CLOSEST TO SAFE (no object declarations)")
    for unit in report["closest_to_safe"]:
        violations = sum(unit[rule] for rule in RULES)
        print("%d\t%s" % (violations, unit["file"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, default=ROOT / "tools/safe-census.json")
    args = parser.parse_args()
    report = census()
    render(report)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("JSON: %s" % args.json.relative_to(ROOT) if args.json.is_relative_to(ROOT) else "JSON: %s" % args.json)


if __name__ == "__main__":
    main()
