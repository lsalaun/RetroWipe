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
import json
import struct
from pathlib import Path

from psx_track_common import (
    DEFAULT_UNITS_PER_METER,
    make_axis_transform,
    parse_cmp,
    parse_prm,
    parse_tim,
    scale_point,
    write_png,
)

# object_draw() in object.c renders a primitive's coords in this order (NOT
# their storage order) -- e.g. `case PRM_TYPE_GT3: ... vertex[coord2],
# vertex[coord1], vertex[coord0]`, and for quads a 2nd triangle
# `vertex[coord2], vertex[coord3], vertex[coord1]`.
TRI3_ORDER = (2, 1, 0)
TRI4_ORDER_A = (2, 1, 0)
TRI4_ORDER_B = (2, 3, 1)


def build_triangle_soup(
    objects: list,
    cmp_entries: list[bytes],
    flip_z: bool,
    units_per_meter: float,
) -> dict:
    """Groups flat/gouraud-shaded triangles by original texture id (None for
    untextured primitives).

    Returns {texture_id: {"positions": [...], "uvs": [...], "colors": [...]}}
    with 3 floats / 2 floats / 4 floats per vertex, 3 vertices per triangle,
    no sharing (matches convert_track_geometry.py's flat triangle-soup style).
    """
    transform, reverse_winding = make_axis_transform(flip_z)
    texture_dims: dict[int, tuple[int, int]] = {}

    def texture_size(index: int) -> tuple[int, int]:
        if index not in texture_dims:
            w, h, _ = parse_tim(cmp_entries[index])
            texture_dims[index] = (w, h)
        return texture_dims[index]

    groups: dict = {}

    for obj in objects:
        ox, oy, oz = obj["origin"]
        world_vertices = [
            scale_point(transform((vx + ox, vy + oy, vz + oz)), units_per_meter)
            for vx, vy, vz in obj["vertices"]
        ]

        for prim in obj["primitives"]:
            coords = prim["coords"]
            texture = prim["texture"]
            colors = [(r / 255.0, g / 255.0, b / 255.0, a / 255.0) for r, g, b, a in prim["colors"]]

            if texture is not None:
                tex_w, tex_h = texture_size(texture)
                uvs = [(u / tex_w, v / tex_h) for u, v in prim["uvs"]]
            else:
                uvs = [(0.0, 0.0)] * len(coords)

            group = groups.setdefault(texture, {"positions": [], "uvs": [], "colors": []})
            order = (0, 2, 1) if reverse_winding else (0, 1, 2)

            def emit_tri(engine_order: tuple[int, int, int]) -> None:
                tri_positions = [world_vertices[coords[i]] for i in engine_order]
                tri_uvs = [uvs[i] for i in engine_order]
                tri_colors = [colors[i] for i in engine_order]
                for k in order:
                    group["positions"].append(tri_positions[k])
                    group["uvs"].append(tri_uvs[k])
                    group["colors"].append(tri_colors[k])

            if len(coords) == 3:
                emit_tri(TRI3_ORDER)
            else:
                emit_tri(TRI4_ORDER_A)
                emit_tri(TRI4_ORDER_B)

    return groups


def export_textures(cmp_entries: list[bytes], texture_ids: set[int], out_dir: Path) -> dict[int, str]:
    """Writes one PNG per texture id actually used, decoded directly from the
    flat SCENE.CMP/SKY.CMP list (no tile assembly, unlike LIBRARY.CMP).
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    texture_files: dict[int, str] = {}
    for texture_id in sorted(texture_ids):
        width, height, pixels = parse_tim(cmp_entries[texture_id])
        filename = f"tex_{texture_id}.png"
        write_png(out_dir / filename, width, height, pixels)
        texture_files[texture_id] = filename
    return texture_files


def write_obj(
    groups: dict,
    out_path: Path,
    texture_files: dict[int, str] | None,
    texture_subdir: str,
) -> None:
    mtl_path = out_path.with_suffix(".mtl")
    lines = [f"mtllib {mtl_path.name}"]
    mtl_lines = []

    vertex_index = 1  # OBJ indices are 1-based
    for group_id in sorted(groups, key=lambda k: (k is None, k)):
        group = groups[group_id]
        positions, uvs, colors = group["positions"], group["uvs"], group["colors"]
        if not positions:
            continue

        mat_name = f"tex_{group_id}" if group_id is not None else "vertex_color"
        avg_color = tuple(sum(c[i] for c in colors) / len(colors) for i in range(3))
        mtl_lines.append(f"newmtl {mat_name}\nKd {avg_color[0]:.4f} {avg_color[1]:.4f} {avg_color[2]:.4f}")
        texture_filename = (texture_files or {}).get(group_id)
        if texture_filename:
            texture_path = f"{texture_subdir}/{texture_filename}" if texture_subdir else texture_filename
            mtl_lines.append(f"map_Kd {texture_path}")
        mtl_lines.append("")

        lines.append(f"g group_{mat_name}")
        lines.append(f"usemtl {mat_name}")

        for p in positions:
            lines.append(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}")
        for uv in uvs:
            lines.append(f"vt {uv[0]:.6f} {uv[1]:.6f}")

        for tri in range(len(positions) // 3):
            a, b, c = (vertex_index + tri * 3 + k for k in range(3))
            lines.append(f"f {a}/{a} {b}/{b} {c}/{c}")
        vertex_index += len(positions)

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    mtl_path.write_text("\n".join(mtl_lines), encoding="utf-8")


def write_gltf(
    groups: dict,
    out_path: Path,
    texture_files: dict[int, str] | None,
    texture_subdir: str,
) -> None:
    bin_path = out_path.with_suffix(".bin")
    buffer_bytes = bytearray()
    buffer_views = []
    accessors = []
    materials = []
    primitives = []
    images = []
    textures = []
    image_index_by_id: dict[int, int] = {}

    def push_floats(values: list[tuple[float, ...]], component_count: int, want_bounds: bool) -> int:
        offset = len(buffer_bytes)
        flat = [c for v in values for c in v]
        buffer_bytes.extend(struct.pack(f"<{len(flat)}f", *flat))
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(flat) * 4, "target": 34962})
        accessor = {
            "bufferView": len(buffer_views) - 1,
            "componentType": 5126,  # FLOAT
            "count": len(values),
            "type": {2: "VEC2", 3: "VEC3", 4: "VEC4"}[component_count],
        }
        if want_bounds:
            cols = list(zip(*values))
            accessor["min"] = [min(c) for c in cols]
            accessor["max"] = [max(c) for c in cols]
        accessors.append(accessor)
        return len(accessors) - 1

    for group_id in sorted(groups, key=lambda k: (k is None, k)):
        group = groups[group_id]
        positions, uvs, colors = group["positions"], group["uvs"], group["colors"]
        if not positions:
            continue

        pos_idx = push_floats(positions, 3, want_bounds=True)
        uv_idx = push_floats(uvs, 2, want_bounds=False)
        color_idx = push_floats(colors, 4, want_bounds=False)

        material: dict = {
            "name": f"tex_{group_id}" if group_id is not None else "vertex_color",
            "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]},
        }
        texture_filename = (texture_files or {}).get(group_id)
        if texture_filename:
            if group_id not in image_index_by_id:
                uri = f"{texture_subdir}/{texture_filename}" if texture_subdir else texture_filename
                images.append({"uri": uri})
                textures.append({"source": len(images) - 1})
                image_index_by_id[group_id] = len(textures) - 1
            material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": image_index_by_id[group_id]}
        materials.append(material)

        primitives.append(
            {
                "attributes": {"POSITION": pos_idx, "TEXCOORD_0": uv_idx, "COLOR_0": color_idx},
                "material": len(materials) - 1,
                "mode": 4,  # TRIANGLES
            }
        )

    gltf = {
        "asset": {"version": "2.0", "generator": "convert_track_scenery.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"uri": bin_path.name, "byteLength": len(buffer_bytes)}],
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures

    bin_path.write_bytes(bytes(buffer_bytes))
    out_path.write_text(json.dumps(gltf), encoding="utf-8")


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
        texture_files = export_textures(cmp_entries, used_texture_ids, texture_dir)
        print(f"Exported {len(texture_files)} texture(s) to {texture_dir}")

    suffix = args.output.suffix.lower()
    if suffix == ".obj":
        write_obj(groups, args.output, texture_files, texture_subdir)
    elif suffix == ".gltf":
        write_gltf(groups, args.output, texture_files, texture_subdir)
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
