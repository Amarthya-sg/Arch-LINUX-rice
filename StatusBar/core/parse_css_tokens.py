#!/usr/bin/env python3
"""Extract --cc-* design tokens from CSS and emit a single-line JSON object.

CSS 8-digit hex colors use #RRGGBBAA, while Qt Quick's 8-digit colors use
#AARRGGBB. Convert between those representations so translucent CSS tokens
retain their intended appearance in QML.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
TOKEN_LINE_RE = re.compile(
    r"^\s*--cc-([a-z][a-z0-9]*(?:-[a-z0-9]+)*)\s*:\s*(.*?)\s*;\s*$"
)
NUMERIC_VALUE_RE = re.compile(
    r"^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(px|ms|s)?$", re.IGNORECASE
)
CSS_HEX_RE = re.compile(r"^#([0-9a-fA-F]{4}|[0-9a-fA-F]{8})$")


def camel_case(name: str) -> str:
    """Convert a lower-kebab token name to lower camelCase."""
    head, *tail = name.split("-")
    return head + "".join(part[0].upper() + part[1:] for part in tail)


def qml_value(value: str) -> int | float | str:
    """Convert CSS numbers, px/ms durations, quoted strings and alpha hex to QML values."""
    match = NUMERIC_VALUE_RE.fullmatch(value)
    if match:
        number = float(match.group(1))
        unit = (match.group(2) or "").lower()
        if unit == "s":
            number *= 1000
        return int(number) if number.is_integer() else number

    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]

    match = CSS_HEX_RE.fullmatch(value)
    if match:
        digits = match.group(1)
        if len(digits) == 8:  # CSS #RRGGBBAA -> Qt #AARRGGBB
            red, green, blue, alpha = digits[0:2], digits[2:4], digits[4:6], digits[6:8]
            return f"#{alpha}{red}{green}{blue}".lower()
        if len(digits) == 4:  # CSS #RGBA -> Qt #ARGB
            red, green, blue, alpha = digits
            return f"#{alpha}{red}{green}{blue}".lower()

    return value


def parse_css(text: str) -> dict[str, int | float | str]:
    """Parse line-oriented --cc-* declarations; reject malformed/duplicate tokens."""
    uncommented = COMMENT_RE.sub(lambda match: "\n" * match.group(0).count("\n"), text)
    tokens: dict[str, int | float | str] = {}

    for line_number, line in enumerate(uncommented.splitlines(), start=1):
        if "--cc-" not in line:
            continue
        match = TOKEN_LINE_RE.fullmatch(line)
        if not match:
            raise ValueError(f"line {line_number}: malformed --cc-* declaration")
        source_name, raw_value = match.groups()
        key = camel_case(source_name)
        if key in tokens:
            raise ValueError(f"line {line_number}: duplicate token --cc-{source_name}")
        value = raw_value.strip()
        if not value:
            raise ValueError(f"line {line_number}: empty value for --cc-{source_name}")
        tokens[key] = qml_value(value)

    if not tokens:
        raise ValueError("no --cc-* custom properties found")
    return tokens


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {Path(argv[0]).name} <style.css>", file=sys.stderr)
        return 1

    css_path = Path(argv[1])
    try:
        text = css_path.read_text(encoding="utf-8")
        tokens = parse_css(text)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"parse_css_tokens: {error}", file=sys.stderr)
        return 1

    print(json.dumps(tokens, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
