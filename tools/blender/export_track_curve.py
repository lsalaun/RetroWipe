"""Exports a Blender Curve object's sampled world-space points to JSON, for
tracks where the curve is used as the AI center line in Godot.

Blender's glTF exporter does not preserve Curve objects (a curve with no
bevel/extrude becomes an empty transform node on export), so this script
samples the Bezier spline directly with Blender's own interpolation and
writes ordered points that Godot can load straight into a Curve3D, bypassing
glTF entirely for this data.

Usage:
    blender --background <file.blend> --python export_track_curve.py -- <output.json> [resolution] [object_name]
"""

import bpy
import mathutils
import json
import sys


def get_script_args():
    argv = sys.argv
    if "--" not in argv:
        return []
    return argv[argv.index("--") + 1:]


def find_curve_object(object_name: str | None):
    if object_name:
        return bpy.data.objects[object_name]
    for obj in bpy.data.objects:
        if obj.type == 'CURVE':
            return obj
    return None


def blender_to_godot(v: mathutils.Vector) -> list[float]:
    # Blender is +Z up; Godot/glTF is +Y up. Matches Blender's own glTF axis conversion.
    return [v.x, v.z, -v.y]


def sample_spline(spline, matrix_world: mathutils.Matrix, resolution: int) -> list[list[float]]:
    points: list[list[float]] = []

    if spline.type == 'BEZIER':
        bp = spline.bezier_points
        n = len(bp)
        segment_count = n if spline.use_cyclic_u else n - 1
        for i in range(segment_count):
            p0 = bp[i]
            p1 = bp[(i + 1) % n]
            segment = mathutils.geometry.interpolate_bezier(
                p0.co, p0.handle_right, p1.handle_left, p1.co, resolution
            )
            start = 0 if i == 0 else 1
            for pt in segment[start:]:
                world_pt = matrix_world @ pt
                points.append(blender_to_godot(world_pt))
    elif spline.type == 'POLY':
        for p in spline.points:
            world_pt = matrix_world @ mathutils.Vector(p.co[:3])
            points.append(blender_to_godot(world_pt))
    else:
        print(f"WARNING: unsupported spline type {spline.type!r}, skipping")

    return points


def main():
    args = get_script_args()
    if not args:
        print("Usage: blender --background <file.blend> --python export_track_curve.py -- <output.json> [resolution] [object_name]")
        sys.exit(1)

    output_path = args[0]
    resolution = int(args[1]) if len(args) > 1 else 16
    object_name = args[2] if len(args) > 2 else None

    obj = find_curve_object(object_name)
    if obj is None:
        print("ERROR: no curve object found")
        sys.exit(1)

    curve = obj.data
    all_points: list[list[float]] = []
    closed = False
    for spline in curve.splines:
        all_points.extend(sample_spline(spline, obj.matrix_world, resolution))
        closed = closed or spline.use_cyclic_u

    data = {"points": all_points, "closed": closed, "source_object": obj.name}
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f)

    print(f"Exported {len(all_points)} points (closed={closed}) to {output_path}")


main()
