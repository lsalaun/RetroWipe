"""Converts wipeout/COMMON PRM+CMP pairs used outside the track folders.

Same PRM/CMP format as convert_ships.py / convert_track_scenery.py. Weapons,
rescue droid and menu models are exported in *local* space (origin not baked),
matching object_draw() with a live transform. EFFECTS.CMP / WICONS.CMP are
texture-only (no PRM).

Usage:
    py convert_common.py wipeout/COMMON out_dir/
    py convert_common.py wipeout/COMMON out_dir/ --only weapons
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from psx_track_common import (
    DEFAULT_UNITS_PER_METER,
    emit_prm_object_triangles,
    export_flat_textures,
    make_axis_transform,
    parse_cmp,
    parse_prm,
    scale_point,
    write_prm_gltf,
)

from convert_textures import convert_file, is_transparent

_SAFE_NAME_RE = re.compile(r"[^a-zA-Z0-9_-]+")

# Groups match how the C engine loads these files.
COMMON_SETS: dict[str, list[tuple[str, str | None, str]]] = {
    "weapons": [
        ("ROCK.PRM", "MINE.CMP", "rocket"),
        ("MINE.PRM", "MINE.CMP", "mine"),
        ("MISS.PRM", "MINE.CMP", "missile"),
        ("SHLD.PRM", "MINE.CMP", "shield"),
        ("EBOLT.PRM", "MINE.CMP", "ebolt"),
    ],
    "droid": [
        ("RESCU.PRM", "RESCU.CMP", "rescue_droid"),
    ],
    "menu": [
        ("LEEG.PRM", "LEEG.CMP", "race_classes"),
        ("TEAMS.PRM", None, "teams"),
        ("PILOT.PRM", "PILOT.CMP", "pilots"),
        ("ALOPT.PRM", "ALOPT.CMP", "options"),
        ("PAD1.PRM", "PAD1.CMP", "controller"),
        ("MSDOS.PRM", "MSDOS.CMP", "misc"),
    ],
    "fx": [
        # texture sheets only
    ],
}

FX_CMP = ("EFFECTS.CMP", "WICONS.CMP")


def safe_filename(name: str, fallback_index: int) -> str:
    cleaned = _SAFE_NAME_RE.sub("_", name.strip()).strip("_")
    return cleaned if cleaned else f"object_{fallback_index}"


def export_prm(
    prm_path: Path,
    cmp_path: Path | None,
    out_dir: Path,
    prefix: str,
    flip_z: bool,
    units_per_meter: float,
) -> None:
    objects = parse_prm(prm_path.read_bytes())
    cmp_entries = parse_cmp(cmp_path.read_bytes()) if cmp_path and cmp_path.is_file() else []
    transform, reverse_winding = make_axis_transform(flip_z)
    out_dir.mkdir(parents=True, exist_ok=True)

    for index, obj in enumerate(objects):
        filename = f"{prefix}_{safe_filename(obj['name'], index)}" if len(objects) > 1 else prefix
        output_path = out_dir / f"{filename}.gltf"
        local_vertices = [scale_point(transform(v), units_per_meter) for v in obj["vertices"]]
        texture_dims: dict[int, tuple[int, int]] = {}
        groups: dict = {}
        emit_prm_object_triangles(local_vertices, obj["primitives"], cmp_entries, reverse_winding, texture_dims, groups)
        texture_files: dict[int, str] = {}
        texture_subdir = f"{filename}_textures"
        used = {k for k in groups if k is not None}
        if used and cmp_entries:
            texture_files = export_flat_textures(cmp_entries, used, out_dir / texture_subdir)
        write_prm_gltf(groups, output_path, texture_files, texture_subdir, generator="convert_common.py")
        triangle_count = sum(len(g["positions"]) // 3 for g in groups.values())
        print(
            f"{prm_path.name} [{index}] {obj['name']!r}: {len(obj['vertices'])} verts, "
            f"{triangle_count} tris -> {output_path.name}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("common", type=Path, help="wipeout/COMMON directory")
    parser.add_argument("output_dir", type=Path, help="Scratch / Godot destination root")
    parser.add_argument("--only", choices=("weapons", "droid", "menu", "fx", "all"), default="all")
    parser.add_argument("--flip-z", action="store_true")
    parser.add_argument("--units-per-meter", type=float, default=DEFAULT_UNITS_PER_METER)
    args = parser.parse_args()

    if not args.common.is_dir():
        raise SystemExit(f"not a directory: {args.common}")

    wanted = list(COMMON_SETS) if args.only == "all" else [args.only]
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for group in wanted:
        if group == "fx":
            fx_dir = args.output_dir / "fx"
            fx_dir.mkdir(parents=True, exist_ok=True)
            for name in FX_CMP:
                src = args.common / name
                if src.is_file():
                    convert_file(src, fx_dir, is_transparent(src, None))
            continue
        dest = args.output_dir / group
        for prm_name, cmp_name, prefix in COMMON_SETS[group]:
            prm = args.common / prm_name
            if not prm.is_file():
                print(f"skip missing {prm}")
                continue
            cmp = args.common / cmp_name if cmp_name else None
            export_prm(prm, cmp, dest, prefix, args.flip_z, args.units_per_meter)

    print(f"done COMMON -> {args.output_dir}")


if __name__ == "__main__":
    main()
