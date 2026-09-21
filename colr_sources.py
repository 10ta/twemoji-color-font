#!/usr/bin/env python3
"""Stage Twemoji SVGs for nanoemoji, adding FE0F alias sequences.

Twemoji file names are not always the sequence people actually type, so a
few extra copies are staged under alternative names; nanoemoji turns each
into its own ligature:

  * keycaps: "23-20e3.svg" also as "23-fe0f-20e3.svg" (the fully-qualified
    form #️⃣ that keyboards emit).
  * sequences containing FE0F, e.g. "1f3f3-fe0f-200d-1f308.svg", also
    without any FE0F, so unqualified input still forms the ligature.

Single-codepoint emoji need nothing: a trailing FE0F is a zero-width glyph.

Usage: colr_sources.py SRC_DIR DEST_DIR
"""
import shutil
import sys
from pathlib import Path

FE0F = "fe0f"


def main(src: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    names = {p.stem.lower(): p for p in src.glob("*.svg")}
    aliases = {}
    for stem, path in names.items():
        parts = stem.split("-")
        if len(parts) == 2 and parts[1] == "20e3":
            aliases["-".join([parts[0], FE0F, "20e3"])] = path
        elif len(parts) > 1 and FE0F in parts:
            stripped = [p for p in parts if p != FE0F]
            if len(stripped) > 1:
                aliases["-".join(stripped)] = path

    for stem, path in names.items():
        shutil.copyfile(path, dest / f"{stem}.svg")
    added = 0
    for stem, path in aliases.items():
        if stem not in names:  # never shadow a real Twemoji file
            shutil.copyfile(path, dest / f"{stem}.svg")
            added += 1
    print(f"Staged {len(names)} SVGs + {added} FE0F aliases into {dest}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))