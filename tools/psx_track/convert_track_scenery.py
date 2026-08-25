"""Converts wipeout-rewrite's trackside scenery/skybox objects (SCENE.PRM +
SCENE.CMP for the grandstands/start gantry/oil pumps/red lights, or SKY.PRM +
SKY.CMP for the sky dome) into a single textured OBJ or glTF 2.0 mesh,
importable directly in Godot or Blender.

Standalone parser (stdlib only, no Blender/bpy required). Mirrors the binary
layout read by objects_load() in wipeout-rewrite's src/wipeout/object.c (see
psx_track_common.py's parse_prm()/parse_cmp()/parse_tim() for the exact
field-by-field port). All PRM reads are big-endian, like TRACK.TRV/TRF/TRS --
see convert_track_geometry.py's module docstring for why. SCENE.CMP/SKY.CMP
differ from LIBRARY.CMP: they are a flat list of standalone textures (no
128x128 tile assembly), one per `texture` index used by a primitive.

Each PRM object is placed at its own `origin` (baked directly into vertex
positions here, since this script produces one static combined mesh rather
than a hierarchy of movable parts -- matching how scene.c's scene_load()
statically positions everything except the handful of objects it re-tags for
per-frame animation, e.g. red lights/oil pumps, which are out of scope for a
static mesh import). Primitives are grouped by their original texture id (OBJ
material groups / glTF primitives), like convert_track_geometry.py. Untextured
(flat/gouraud-shaded) primitives are grouped separately and keep their
original per-vertex colors via glTF's COLOR_0 attribute (or a flattened
average Kd for the simpler OBJ output). Sprites (TSPR/BSPR), splines and
lights are parsed (to keep the primitive stream aligned) but produce no mesh
geometry -- see the summary counts printed at the end of a run.

Usage:
    python convert_track_scenery.py SCENE.PRM SCENE.CMP scene.gltf
    python convert_track_scenery.py SKY.PRM SKY.CMP sky.gltf --flip-z
"""

from __future__ import annotations

import argparse
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


def build_triangle_soup(
    objects: list,
    cmp_entries: list[bytes],
    flip_z: bool,
    units_per_meter: float,
) -> dict:
    """Groups flat/gouraud-shaded triangles by original texture id (None for
    untextured primitives), across all objects (each placed at its own
    `origin`, baked directly into vertex positions -- see this module's
    docstring for why).

    Returns {texture_id: {"positions": [...], "uvs": [...], "colors": [...]}}
    with 3 floats / 2 floats / 4 floats per vertex, 3 vertices per triangle,
    no sharing (matches convert_track_geometry.py's flat triangle-soup style).
    """
    transform, reverse_winding = make_axis_transform(flip_z)
    texture_dims: dict[int, tuple[int, int]] = {}
    groups: dict = {}

    for obj in objects:
        ox, oy, oz = obj["origin"]
        world_vertices = [
            scale_point(transform((vx + ox, vy + oy, vz + oz)), units_per_meter)
            for vx, vy, vz in obj["vertices"]
        ]
        emit_prm_object_triangles(world_vertices, obj["primitives"], cmp_entries, reverse_winding, texture_dims, groups)

    return groups


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("prm", type=Path, help="Path to SCENE.PRM or SKY.PRM")
    parser.add_argument("cmp", type=Path, help="Path to SCENE.CMP or SKY.CMP")
    parser.add_argument("output", type=Path, help="Output .obj or .gltf path")
    parser.add_argument(
        "--flip-z", action="store_true",
        help="Also negate Z, keep in sync with convert_track_geometry.py for this same track",
    )
    parser.add_argument(
        "--units-per-meter", type=float, default=DEFAULT_UNITS_PER_METER,
        help=f"Raw PSX units per meter (default {DEFAULT_UNITS_PER_METER}). Keep in sync with convert_track_geometry.py for this same track.",
    )
    parser.add_argument("--no-textures", action="store_true", help="Skip texture export, keep only vertex colors")
    args = parser.parse_args()

    objects = parse_prm(args.prm.read_bytes())
    cmp_entries = parse_cmp(args.cmp.read_bytes())
    groups = build_triangle_soup(objects, cmp_entries, args.flip_z, args.units_per_meter)

    texture_files: dict[int, str] = {}
    texture_subdir = f"{args.output.stem}_textures"
    used_texture_ids = {k for k in groups if k is not None}
    if not args.no_textures and used_texture_ids:
        texture_dir = args.output.parent / texture_subdir
        texture_files = export_flat_textures(cmp_entries, used_texture_ids, texture_dir)
        print(f"Exported {len(texture_files)} texture(s) to {texture_dir}")

    suffix = args.output.suffix.lower()
    if suffix == ".obj":
        write_prm_obj(groups, args.output, texture_files, texture_subdir)
    elif suffix == ".gltf":
        write_prm_gltf(groups, args.output, texture_files, texture_subdir, generator="convert_track_scenery.py")
    else:
        raise SystemExit(f"Unsupported output extension {suffix!r}, use .obj or .gltf")

    triangle_count = sum(len(g["positions"]) // 3 for g in groups.values())
    mesh_primitive_count = sum(len(o["primitives"]) for o in objects)
    print(
        f"Parsed {len(objects)} objects, {mesh_primitive_count} mesh primitives "
        f"-> {triangle_count} triangles across {len(groups)} material group(s). "
        f"Wrote {args.output}"
    )


if __name__ == "__main__":
    main()
