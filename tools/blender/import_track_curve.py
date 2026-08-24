"""Creates a Blender Bezier curve object from a track centerline JSON (as
produced by godot/tools/psx_track/convert_track_sections.py or
godot/tools/blender/export_track_curve.py's own output format: a dict with
"points" (list of [x, y, z]) and "closed" (bool)), and saves it to a new
.blend file. This is the inverse of export_track_curve.py, for reimporting a
converted PSX track's racing line into Blender for inspection/editing.

The JSON points are in Godot/glTF space (+Y up), matching
export_track_curve.py's own blender_to_godot() convention
(godot = [blender.x, blender.z, -blender.y]), so this script applies the
exact inverse (blender = (godot.x, -godot.z, godot.y)) to land back in
Blender's +Z-up space.

Usage:
    blender --background --python import_track_curve.py -- <input.json> <output.blend> [object_name]
"""

import bpy
import json
import sys


def get_script_args():
    argv = sys.argv
    if "--" not in argv:
        return []
    return argv[argv.index("--") + 1:]


def godot_to_blender(p: list[float]) -> tuple[float, float, float]:
    x, y, z = p
    return (x, -z, y)


def build_curve_object(points: list[list[float]], closed: bool, name: str) -> bpy.types.Object:
    curve_data = bpy.data.curves.new(name, type='CURVE')
    curve_data.dimensions = '3D'

    spline = curve_data.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)  # one point already exists
    spline.use_cyclic_u = closed

    for bp, point in zip(spline.bezier_points, points):
        bp.co = godot_to_blender(point)
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'

    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def main() -> None:
    args = get_script_args()
    if len(args) < 2:
        print("Usage: blender --background --python import_track_curve.py -- <input.json> <output.blend> [object_name]")
        sys.exit(1)

    input_path = args[0]
    output_path = args[1]
    object_name = args[2] if len(args) > 2 else "TrackCenterLine"

    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    points = data["points"]
    closed = bool(data.get("closed", False))
    if len(points) < 2:
        print("ERROR: JSON has fewer than 2 points")
        sys.exit(1)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    obj = build_curve_object(points, closed, object_name)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.wm.save_as_mainfile(filepath=output_path)
    print(f"Wrote {len(points)} points (closed={closed}) as '{object_name}' to {output_path}")


main()
