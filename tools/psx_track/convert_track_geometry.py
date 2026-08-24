"""Converts the original PSX WipEout track geometry (TRACK.TRV + TRACK.TRF)
into a plain OBJ or glTF 2.0 mesh, importable directly in Godot or in Blender
for manual cleanup (retopo, UV, LODs) before re-export.

This is a standalone parser (stdlib only, no Blender/bpy required) that
mirrors the binary layout read by track_load_vertices()/track_load_faces()
in wipeout-rewrite's src/wipeout/track.c:

    TRACK.TRV: 16 bytes/vertex -> int32 x, y, z (big-endian), then 4 bytes
                                  padding.
    TRACK.TRF: 20 bytes/face   -> int16 v0,v1,v2,v3 (quad vertex indices,
                                  big-endian), int16 nx,ny,nz (normal,
                                  fixed-point /4096, big-endian), uint8
                                  texture id, uint8 flags, uint32 color.
    Big-endian is not a typo: utils.h's get_i16()/get_i32() (used by
    track_load_vertices()/track_load_faces(), as opposed to the _le variants)
    read MSB-first, most likely a leftover of asset tooling built on
    big-endian MIPS workstations of the era despite the PSX CPU itself being
    little-endian. Verified empirically against real TRACK01 data: reading
    little-endian gives garbage (vertex indices to invalid indices, normals
    far from unit length); big-endian gives indices within range and unit
    normals.
    Each face is two triangles: (v0,v1,v2) and (v3,v0,v2), flat shaded with
    the face's single normal (this matches ship.c/track.c's own tris[0]/[1]
    construction).

Coordinate system: the source engine's world Y axis points down (evidenced
by camera.c's ship->mat.basis.down usage, and confirmed by testing against
real TRACK01 data: raw face normals for track-surface faces have a negative
Y component, which only cancels out SHIP_ON_TRACK_GRAVITY's *positive* Y
push in ship_player.c's hover equilibrium if +Y points down). Godot/glTF use
+Y up, so by default this script negates Y and reverses triangle winding to
compensate (a single axis flip inverts handedness). Still worth a visual
sanity check in Blender on a new track before trusting it blindly; use
--flip-z if the geometry comes out mirrored left/right.

Texture UVs use the original's fixed per-face tile layout (a 128x128 unit
tile per face, flipped for FACE_FLIP_TEXTURE) normalized to 0..1 -- this is
NOT a real texture atlas mapping (LIBRARY.CMP/TTF is out of scope here), it
only gives every face a well-formed local UV square to re-map textures onto
later. Faces are grouped by their original texture id (OBJ material groups /
glTF primitives) so that grouping survives into Blender/Godot.

Usage:
    python convert_track_geometry.py TRACK.TRV TRACK.TRF output.obj
    python convert_track_geometry.py TRACK.TRV TRACK.TRF output.gltf --flip-z
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path

from psx_track_common import make_axis_transform

VERTEX_STRUCT = struct.Struct(">3i4x")  # x, y, z (int32, big-endian), 4 bytes padding
FACE_STRUCT = struct.Struct(">4h3hBBI")  # v0..v3, nx,ny,nz, texture, flags, color (big-endian)

FACE_FLIP_TEXTURE = 1 << 2
TILE_SIZE = 128.0

# Matches wipeout-rewrite's track_uv[] table in track.c, indexed [flip][corner].
TILE_UV = [
    [(128, 0), (0, 0), (0, 128), (128, 128)],
    [(0, 0), (128, 0), (128, 128), (0, 128)],
]


@dataclass
class Face:
    indices: tuple[int, int, int, int]
    normal: tuple[float, float, float]
    texture: int
    flags: int


def parse_trv(path: Path) -> list[tuple[float, float, float]]:
    data = path.read_bytes()
    count = len(data) // VERTEX_STRUCT.size
    return [VERTEX_STRUCT.unpack_from(data, i * VERTEX_STRUCT.size) for i in range(count)]


def parse_trf(path: Path) -> list[Face]:
    data = path.read_bytes()
    count = len(data) // FACE_STRUCT.size
    faces = []
    for i in range(count):
        v0, v1, v2, v3, nx, ny, nz, texture, flags, _color = FACE_STRUCT.unpack_from(
            data, i * FACE_STRUCT.size
        )
        normal = (nx / 4096.0, ny / 4096.0, nz / 4096.0)
        faces.append(Face((v0, v1, v2, v3), normal, texture, flags))
    return faces


def build_triangle_soup(
    vertices: list[tuple[float, float, float]],
    faces: list[Face],
    flip_z: bool,
) -> dict[int, dict[str, list]]:
    """Groups flat-shaded triangles by original texture id.

    Returns {texture_id: {"positions": [...], "normals": [...], "uvs": [...]}}
    with 3 floats / 2 floats per vertex, 3 vertices per triangle, no sharing
    (flat shading makes vertex de-duplication pointless here; Blender's
    "merge by distance" can weld the seams if a smooth mesh is wanted later).
    """
    transform, reverse_winding = make_axis_transform(flip_z)
    groups: dict[int, dict[str, list]] = {}

    for face in faces:
        v0, v1, v2, v3 = (transform(vertices[i]) for i in face.indices)
        normal = transform(face.normal)
        flip = bool(face.flags & FACE_FLIP_TEXTURE)
        uv_table = TILE_UV[1 if flip else 0]
        uv = [(u / TILE_SIZE, w / TILE_SIZE) for u, w in uv_table]

        tris = [
            ((v0, v1, v2), (uv[0], uv[1], uv[2])),
            ((v3, v0, v2), (uv[3], uv[0], uv[2])),
        ]

        group = groups.setdefault(face.texture, {"positions": [], "normals": [], "uvs": []})
        for tri_verts, tri_uvs in tris:
            order = (0, 2, 1) if reverse_winding else (0, 1, 2)
            for i in order:
                group["positions"].append(tri_verts[i])
                group["normals"].append(normal)
                group["uvs"].append(tri_uvs[i])

    return groups


def write_obj(groups: dict[int, dict[str, list]], out_path: Path) -> None:
    mtl_path = out_path.with_suffix(".mtl")
    lines = [f"mtllib {mtl_path.name}"]
    mtl_lines = []

    vertex_index = 1  # OBJ indices are 1-based
    for texture_id in sorted(groups):
        group = groups[texture_id]
        mat_name = f"tex_{texture_id}"
        mtl_lines.append(f"newmtl {mat_name}\nKd 1.0 1.0 1.0\n")
        lines.append(f"g face_texture_{texture_id}")
        lines.append(f"usemtl {mat_name}")

        positions = group["positions"]
        normals = group["normals"]
        uvs = group["uvs"]
        for p in positions:
            lines.append(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}")
        for n in normals:
            lines.append(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}")
        for uv in uvs:
            lines.append(f"vt {uv[0]:.6f} {uv[1]:.6f}")

        for tri in range(len(positions) // 3):
            a, b, c = (vertex_index + tri * 3 + k for k in range(3))
            lines.append(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}")
        vertex_index += len(positions)

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    mtl_path.write_text("\n".join(mtl_lines), encoding="utf-8")


def write_gltf(groups: dict[int, dict[str, list]], out_path: Path) -> None:
    bin_path = out_path.with_suffix(".bin")
    buffer_bytes = bytearray()
    buffer_views = []
    accessors = []
    materials = []
    primitives = []

    def push_floats(values: list[tuple[float, ...]], component_count: int, want_bounds: bool):
        offset = len(buffer_bytes)
        flat = [c for v in values for c in v]
        buffer_bytes.extend(struct.pack(f"<{len(flat)}f", *flat))
        buffer_views.append(
            {
                "buffer": 0,
                "byteOffset": offset,
                "byteLength": len(flat) * 4,
                "target": 34962,  # ARRAY_BUFFER
            }
        )
        accessor = {
            "bufferView": len(buffer_views) - 1,
            "componentType": 5126,  # FLOAT
            "count": len(values),
            "type": {2: "VEC2", 3: "VEC3"}[component_count],
        }
        if want_bounds:
            cols = list(zip(*values))
            accessor["min"] = [min(c) for c in cols]
            accessor["max"] = [max(c) for c in cols]
        accessors.append(accessor)
        return len(accessors) - 1

    for texture_id in sorted(groups):
        group = groups[texture_id]
        pos_idx = push_floats(group["positions"], 3, want_bounds=True)
        norm_idx = push_floats(group["normals"], 3, want_bounds=False)
        uv_idx = push_floats(group["uvs"], 2, want_bounds=False)

        materials.append({"name": f"tex_{texture_id}", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]}})
        primitives.append(
            {
                "attributes": {"POSITION": pos_idx, "NORMAL": norm_idx, "TEXCOORD_0": uv_idx},
                "material": len(materials) - 1,
                "mode": 4,  # TRIANGLES
            }
        )

    gltf = {
        "asset": {"version": "2.0", "generator": "convert_track_geometry.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"uri": bin_path.name, "byteLength": len(buffer_bytes)}],
    }

    bin_path.write_bytes(bytes(buffer_bytes))
    out_path.write_text(json.dumps(gltf), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("trv", type=Path, help="Path to TRACK.TRV")
    parser.add_argument("trf", type=Path, help="Path to TRACK.TRF")
    parser.add_argument("output", type=Path, help="Output .obj or .gltf path")
    parser.add_argument(
        "--flip-z", action="store_true",
        help="Also negate Z (use if the track comes out mirrored after a first conversion)",
    )
    args = parser.parse_args()

    vertices = parse_trv(args.trv)
    faces = parse_trf(args.trf)
    groups = build_triangle_soup(vertices, faces, args.flip_z)

    suffix = args.output.suffix.lower()
    if suffix == ".obj":
        write_obj(groups, args.output)
    elif suffix in (".gltf",):
        write_gltf(groups, args.output)
    else:
        raise SystemExit(f"Unsupported output extension {suffix!r}, use .obj or .gltf")

    triangle_count = sum(len(g["positions"]) // 3 for g in groups.values())
    print(
        f"Parsed {len(vertices)} vertices, {len(faces)} faces "
        f"-> {triangle_count} triangles across {len(groups)} texture groups. "
        f"Wrote {args.output}"
    )
    print("Verify orientation in Blender/Godot: track should read right-side-up, "
          "face normals should point away from the drivable surface. "
          "Re-run with --flip-z if the geometry is mirrored.")


if __name__ == "__main__":
    main()
