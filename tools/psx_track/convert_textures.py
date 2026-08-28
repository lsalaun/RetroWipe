"""Converts wipeout/TEXTURES (and optional COMMON CMP/TIM) to PNG for Godot.

Standalone (stdlib only). TIM files are decoded with parse_tim() (little-endian
image.c path). CMP files are a flat list of TIM entries (parse_cmp + parse_tim),
same as SCENE.CMP / ALLSH.CMP -- not LIBRARY.CMP tile assembly.

Usage:
    py convert_textures.py wipeout/TEXTURES out_dir/
    py convert_textures.py wipeout/TEXTURES/speedo.tim out.png
    py convert_textures.py wipeout/TEXTURES/shad1.tim out.png --transparent
"""

from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path

from psx_track_common import parse_cmp, parse_tim, write_png

_SAFE_RE = re.compile(r"[^a-zA-Z0-9_-]+")

# image_get_texture_semi_trans() in image.c / ship.c / weapon.c
DEFAULT_TRANSPARENT_STEMS = {
    "shad1",
    "shad2",
    "shad3",
    "shad4",
    "target2",
}


def safe_stem(name: str) -> str:
    cleaned = _SAFE_RE.sub("_", name.strip()).strip("_")
    return cleaned.lower() if cleaned else "tex"


def export_tim(data: bytes, out_path: Path, transparent: bool) -> tuple[int, int]:
    width, height, pixels = parse_tim(data, transparent=transparent)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(out_path, width, height, pixels)
    return width, height


def export_cmp(data: bytes, out_dir: Path, stem: str, transparent: bool) -> int:
    entries = parse_cmp(data)
    out_dir.mkdir(parents=True, exist_ok=True)
    written = 0
    for index, entry in enumerate(entries):
        if not entry:
            continue
        try:
            width, height, pixels = parse_tim(entry, transparent=transparent)
        except (struct.error, ValueError, IndexError) as extra:
            print(f"  skip {stem}[{index}]: {extra}")
            continue
        out_path = out_dir / f"{stem}_{index:02d}.png"
        write_png(out_path, width, height, pixels)
        written += 1
    return written



def is_transparent(path: Path, force: bool | None) -> bool:
    if force is not None:
        return force
    return path.stem.lower() in DEFAULT_TRANSPARENT_STEMS


def convert_file(path: Path, output: Path, transparent: bool | None) -> None:
    suffix = path.suffix.lower()
    trans = is_transparent(path, transparent)
    if suffix == ".tim":
        dest = output if output.suffix.lower() == ".png" else output / f"{safe_stem(path.stem)}.png"
        w, h = export_tim(path.read_bytes(), dest, trans)
        print(f"{path.name}: TIM {w}x{h} transparent={trans} -> {dest}")
        return
    if suffix == ".cmp":
        dest_dir = output.parent / safe_stem(path.stem) if output.suffix.lower() == ".png" else output / safe_stem(path.stem)
        count = export_cmp(path.read_bytes(), dest_dir, safe_stem(path.stem), trans)
        print(f"{path.name}: CMP {count} image(s) transparent={trans} -> {dest_dir}")
        return
    raise SystemExit(f"Unsupported texture file {path} (need .tim or .cmp)")


def convert_dir(src: Path, out_dir: Path, transparent: bool | None) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in src.iterdir() if p.is_file() and p.suffix.lower() in {".tim", ".cmp"})
    if not files:
        raise SystemExit(f"No .tim/.cmp files in {src}")
    for path in files:
        suffix = path.suffix.lower()
        trans = is_transparent(path, transparent)
        stem = safe_stem(path.stem)
        if suffix == ".tim":
            dest = out_dir / f"{stem}.png"
            try:
                w, h = export_tim(path.read_bytes(), dest, trans)
            except (struct.error, ValueError, IndexError) as exc:
                print(f"{path.name}: skip ({exc})")
                continue
            print(f"{path.name}: TIM {w}x{h} -> {dest.name}")
        else:
            dest_dir = out_dir / stem
            try:
                count = export_cmp(path.read_bytes(), dest_dir, stem, trans)
            except (struct.error, ValueError, IndexError) as exc:
                print(f"{path.name}: skip ({exc})")
                continue
            print(f"{path.name}: CMP {count} image(s) -> {dest_dir.name}/")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="A .tim/.cmp file, or a folder of them (wipeout/TEXTURES)")
    parser.add_argument("output", type=Path, help="Output PNG path or directory")
    parser.add_argument(
        "--transparent",
        action="store_true",
        default=None,
        help="Force TIM transparent-bit handling (default: on for shad1-4/target2)",
    )
    parser.add_argument(
        "--opaque",
        action="store_true",
        help="Force opaque decode even for shad*/target2",
    )
    args = parser.parse_args()

    transparent: bool | None
    if args.opaque:
        transparent = False
    elif args.transparent:
        transparent = True
    else:
        transparent = None

    if args.source.is_dir():
        convert_dir(args.source, args.output, transparent)
    elif args.source.is_file():
        convert_file(args.source, args.output, transparent)
    else:
        raise SystemExit(f"Source not found: {args.source}")


if __name__ == "__main__":
    main()
