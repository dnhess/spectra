#!/usr/bin/env python3
"""Scan text for prompt injection patterns per shared/security.md.

Usage: python3 check_sanitization.py '<text>'
Exit 0 if clean, exit 1 with matched patterns on stderr.
"""

import re
import sys

PATTERNS = [
    # System prompt fragments
    (r"\bYou are\b", "system_prompt"),
    (r"\bYour role is\b", "system_prompt"),
    (r"\bInstructions:", "system_prompt"),
    (r"\bSystem:", "system_prompt"),
    # Tool invocation
    (r"<tool>", "tool_invocation"),
    (r"<function_call>", "tool_invocation"),
    (r"<invoke>", "tool_invocation"),
    # Role redefinition
    (r"\bIgnore previous\b", "role_redefinition"),
    (r"\bNew instructions\b", "role_redefinition"),
    (r"\bAs an AI\b", "role_redefinition"),
]

COMPILED = [(re.compile(p, re.IGNORECASE), cat) for p, cat in PATTERNS]


def check(text):
    matches = []
    for regex, category in COMPILED:
        if regex.search(text):
            matches.append(f"{category}: matched '{regex.pattern}'")
    return matches


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 check_sanitization.py '<text>'", file=sys.stderr)
        sys.exit(1)

    matches = check(sys.argv[1])
    if matches:
        for m in matches:
            print(m, file=sys.stderr)
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
