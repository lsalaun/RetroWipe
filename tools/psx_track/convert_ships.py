"""Converts wipeout-rewrite's ship models (COMMON/ALLSH.PRM + COMMON/ALLSH.CMP)
into one textured OBJ or glTF 2.0 mesh per ship, importable directly in Godot
or Blender. The same script also works on COMMON/ALCOL.PRM + COMMON/ALCOL.CMP
(the low-poly collision models used by ship_intersects_ship() in ship.c) --
it's the same PRM/CMP format either way.

Standalone parser (stdlib only, no Blender/bpy required). Mirrors the binary
layout read by objects_load() in wipeout-rewrite's src/wipeout/object.c (see
psx_track_common.py's parse_prm()/parse_cmp()/parse_tim() for the exact
field-by-field port) -- same format as convert_track_scenery.py's SCENE.PRM/
SKY.PRM, but each PRM object here is one full ship (ALLSH.PRM has 8 objects,
named after their pilot: sophia, solaar, jacko, chang, arian, arial, anasta,
Dekka -- see def.pilots in src/wipeout/game.c for the full pilot roster).

Unlike convert_track_scenery.py, each object's `origin` is NOT baked into its
vertex positions: ships_load() in ship.c never applies it (object_draw() is
called with the ship's own live transform, not a translation derived from
`origin`), so it appears to be vestigial for this particular use of the
Object format. Vertices are exported in the model's own local space, ready to
be parented under a ship's root node in Godot.

Usage:
    python convert_ships.py COMMON/ALLSH.PRM COMMON/ALLSH.CMP out_dir/
    python convert_ships.py COMMON/ALCOL.PRM COMMON/ALCOL.CMP out_dir/ --format obj
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
    write_prm_obj,
)

_SAFE_NAME_RE = re.compile(r"[^a-zA-Z0-9_-]+")


def safe_filename(name: str, fallback_index: int) -> str:
    cleaned = _SAFE_NAME_RE.sub("_", name.strip()).strip("_")
    return cleaned if cleaned else f"ship_{fallback_index}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("prm", type=Path, help="Path to ALLSH.PRM (or ALCOL.PRM)")
    parser.add_argument("cmp", type=Path, help="Path to ALLSH.CMP (or ALCOL.CMP)")
    parser.add_argument("output_dir", type=Path, help="Directory to write one mesh (+ textures) per ship into")
    parser.add_argument("--format", choices=("gltf", "obj"), default="gltf", help="Output format (default gltf)")
    parser.add_argument(
        "--flip-z", action="store_true",
        help="Also negate Z (use if a ship comes out mirrored)",
    )
    parser.add_argument(
        "--units-per-meter", type=float, default=DEFAULT_UNITS_PER_METER,
        help=f"Raw PSX units per meter (default {DEFAULT_UNITS_PER_METER}). Pass 1.0 to keep raw PSX units.",
    )
    parser.add_argument("--no-textures", action="store_true", help="Skip texture export, keep only vertex colors")
    args = parser.parse_args()

    objects = parse_prm(args.prm.read_bytes())
    cmp_entries = parse_cmp(args.cmp.read_bytes())
    transform, reverse_winding = make_axis_transform(args.flip_z)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    for index, obj in enumerate(objects):
        filename = safe_filename(obj["name"], index)
        output_path = args.output_dir / f"{filename}.{args.format}"

        local_vertices = [scale_point(transform(v), args.units_per_meter) for v in obj["vertices"]]
        texture_dims: dict[int, tuple[int, int]] = {}
        groups: dict = {}
        emit_prm_object_triangles(local_vertices, obj["primitives"], cmp_entries, reverse_winding, texture_dims, groups)

        texture_files: dict[int, str] = {}
        texture_subdir = f"{filename}_textures"
        used_texture_ids = {k for k in groups if k is not None}
        if not args.no_textures and used_texture_ids:
            texture_files = export_flat_textures(cmp_entries, used_texture_ids, args.output_dir / texture_subdir)

        if args.format == "obj":
            write_prm_obj(groups, output_path, texture_files, texture_subdir)
        else:
            write_prm_gltf(groups, output_path, texture_files, texture_subdir, generator="convert_ships.py")

        triangle_count = sum(len(g["positions"]) // 3 for g in groups.values())
        print(
            f"[{index}] {obj['name']!r}: {len(obj['vertices'])} vertices, {len(obj['primitives'])} primitives "
            f"-> {triangle_count} triangles, {len(texture_files)} texture(s). Wrote {output_path}"
        )


if __name__ == "__main__":
    main()
