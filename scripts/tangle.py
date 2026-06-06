#!/usr/bin/env python3
"""
Org-tangle: extract Wolfram Language source blocks from .org files
into .wl / .wlt files.

Convention:
- Block headers like `#+BEGIN_SRC wolfram` are extracted.
- Blocks tagged with `#+PROPERTY: tangle Advices.wl` (file-level) are
  extracted only if the requested output file matches the tangle target.
- Otherwise, all blocks with `#+PROPERTY: tangle <name>` on the same
  line as the BEGIN_SRC are extracted into <name>.

This is intentionally simple — no full Org parser. It handles the
patterns used in this project.
"""

import re
import sys
from pathlib import Path

BEGIN_RE = re.compile(r'#\+BEGIN_SRC\s+wolfram\b(.*?)$', re.MULTILINE)
END_RE = re.compile(r'#\+END_SRC\b', re.MULTILINE)


def tangle(org_path: Path) -> None:
    text = org_path.read_text()

    # Find file-level default tangle target
    file_tangle = None
    for m in re.finditer(r'#\+PROPERTY:\s+tangle\s+(\S+)\s*$', text, re.MULTILINE):
        file_tangle = m.group(1)
        break

    # Walk the file linearly, finding BEGIN_SRC...END_SRC blocks
    pos = 0
    outputs: dict[str, list[str]] = {}
    for begin_match in BEGIN_RE.finditer(text):
        start = begin_match.end()
        end_match = END_RE.search(text, start)
        if not end_match:
            continue
        body = text[start:end_match.start()]
        # Find the END of the BEGIN_SRC line and check for a per-block tangle
        begin_line = text[begin_match.start():begin_match.end()]
        per_block = re.search(r':tangle\s+(\S+)', begin_line)
        target = per_block.group(1) if per_block else file_tangle
        if not target:
            # No tangle target at all — skip
            continue
        outputs.setdefault(target, []).append(body)
        pos = end_match.end()

    for target, blocks in outputs.items():
        out = org_path.parent / target
        # Strip trailing whitespace per block but keep newlines for readability
        content = '\n'.join(b.rstrip() + '\n' for b in blocks)
        out.write_text(content)
        print(f"  tangled {len(blocks):2d} blocks -> {out.name} ({len(content):5d} bytes)")


def main():
    if len(sys.argv) < 2:
        print("Usage: tangle.py file.org [file2.org ...]")
        sys.exit(1)
    for arg in sys.argv[1:]:
        p = Path(arg)
        print(f"Tangling {p} ...")
        tangle(p)


if __name__ == '__main__':
    main()
