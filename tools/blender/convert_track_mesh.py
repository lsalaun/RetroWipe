"""Imports a track mesh (glTF, with its textures) into an empty Blender
scene and re-exports it as a self-contained .glb for Godot import. This is
the mesh counterpart to export_track_curve.py/import_track_curve.py, which
only handle the AI centerline -- see godot/tools/psx_track/
convert_track_geometry.py for how the source .gltf (+ per-face texture PNGs)
gets produced from the original PSX TRACK.TRV/TRF/LIBRARY.CMP/TTF data.

Usage:
    blender --background --python convert_track_mesh.py -- <input.gltf> <output.glb>
"""

import bpy
import sys
from pathlib import Path


def get_script_args():
    argv = sys.argv
    if "--" not in argv:
        return []
    return argv[argv.index("--") + 1:]


def main() -> None:
    args = get_script_args()
    if len(args) < 2:
        print("Usage: blender --background --python convert_track_mesh.py -- <input.gltf> <output.glb>")
        sys.exit(1)

    input_path = Path(args[0])
    output_path = Path(args[1])

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(input_path))

    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        export_image_format="AUTO",
        export_yup=True,
    )
    print(f"Wrote {output_path}")


main()
