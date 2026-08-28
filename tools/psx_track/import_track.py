"""End-to-end PSX TRACKNN -> Godot import (pipeline A).

Runs convert_track_geometry/sections/face_flags/scenery, re-exports glTF to
GLB via Blender, copies livrables into godot/src/assets/tracks/Track_NN/,
and prints the yaw-only ShipSpawn Transform3D.

Always passes --flip-z and the same --units-per-meter to every converter.

Usage (from anywhere):
    py godot/tools/psx_track/import_track.py TRACK01
    py godot/tools/psx_track/import_track.py 12 --skip-blender
    py godot/tools/psx_track/import_track.py TRACK15 --write-scene
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from circuit_catalog import CIRCUITS, folder_key, spawn_section_index
from compute_ship_spawn import yaw_only_transform
from psx_track_common import DEFAULT_UNITS_PER_METER

TOOLS_DIR = Path(__file__).resolve().parent
GODOT_DIR = TOOLS_DIR.parent.parent
REPO_ROOT = GODOT_DIR.parent
BLENDER_CONVERT = GODOT_DIR / "tools" / "blender" / "convert_track_mesh.py"
DEFAULT_GODOT = Path(r"d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe")


def track_number(raw: str) -> str:
    text = raw.strip().upper()
    if text.startswith("TRACK"):
        text = text[5:]
    if not text.isdigit():
        raise SystemExit(f"expected TRACKNN or NN, got {raw!r}")
    return f"{int(text):02d}"


def run_py(script: Path, *args: str) -> None:
    cmd = [sys.executable, str(script), *args]
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True, cwd=str(TOOLS_DIR))


def run_blender(gltf: Path, glb: Path) -> None:
    cmd = ["blender", "--background", "--python", str(BLENDER_CONVERT), "--", str(gltf), str(glb)]
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def copy_if_exists(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    print(f"copied {src.name} -> {dest}")


def write_track_scene(nn: str, dest: Path, spawn_literal: str) -> None:
    folder = f"Track_{nn}"
    node = f"Track{nn}"
    content = f"""[gd_scene format=3]

[ext_resource type="PackedScene" path="res://assets/tracks/{folder}/Track_{nn}_mesh.glb" id="1_mesh"]
[ext_resource type="Script" path="res://scripts/track_center_line.gd" id="2_script"]
[ext_resource type="Script" path="res://scripts/track_mesh_collider.gd" id="3_script"]
[ext_resource type="PackedScene" path="res://assets/tracks/{folder}/Track_{nn}_scene.glb" id="4_scene"]
[ext_resource type="PackedScene" path="res://assets/tracks/{folder}/Track_{nn}_sky.glb" id="5_sky"]
[ext_resource type="Script" path="res://scripts/track_gameplay_zones.gd" id="6_script"]

[node name="{node}" type="Node3D"]
script = ExtResource("3_script")

[node name="TrackMesh" parent="." instance=ExtResource("1_mesh")]

[node name="Scenery" parent="." instance=ExtResource("4_scene")]

[node name="Sky" parent="." instance=ExtResource("5_sky")]

[node name="CenterLine" type="Path3D" parent="."]
script = ExtResource("2_script")
source_json = "res://assets/tracks/{folder}/track_{nn}_curve.json"

[node name="GameplayZones" type="Node3D" parent="."]
script = ExtResource("6_script")
source_json = "res://assets/tracks/{folder}/track_{nn}_face_flags.json"

[node name="ShipSpawn" type="Marker3D" parent="."]
transform = {spawn_literal}
"""
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding="utf-8")
    print(f"wrote scene {dest}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("track", help="TRACKNN or NN (01-15)")
    parser.add_argument("--wipeout-root", type=Path, default=REPO_ROOT / "wipeout")
    parser.add_argument("--scratch", type=Path, default=REPO_ROOT / "_converted_tracks")
    parser.add_argument("--godot-assets", type=Path, default=GODOT_DIR / "src" / "assets" / "tracks")
    parser.add_argument("--units-per-meter", type=float, default=DEFAULT_UNITS_PER_METER)
    parser.add_argument("--no-flip-z", action="store_true", help="Do not pass --flip-z (not recommended)")
    parser.add_argument("--skip-blender", action="store_true", help="Stop after glTF/JSON; do not write GLB")
    parser.add_argument("--skip-copy", action="store_true", help="Do not copy into godot/src/assets")
    parser.add_argument("--write-scene", action="store_true", help="Write godot/src/scenes/TrackNN.tscn if missing")
    parser.add_argument("--overwrite-scene", action="store_true", help="Overwrite an existing TrackNN.tscn")
    parser.add_argument("--godot-import", action="store_true", help="Run Godot --headless --import after copy")
    parser.add_argument("--godot-bin", type=Path, default=DEFAULT_GODOT)
    args = parser.parse_args()

    nn = track_number(args.track)
    folder = f"TRACK{nn}"
    src = args.wipeout_root / folder
    if not src.is_dir():
        raise SystemExit(f"missing PSX folder {src}")

    required = ["TRACK.TRV", "TRACK.TRF", "TRACK.TRS", "LIBRARY.CMP", "LIBRARY.TTF", "SCENE.PRM", "SCENE.CMP", "SKY.PRM", "SKY.CMP"]
    missing = [name for name in required if not (src / name).is_file()]
    if missing:
        raise SystemExit(f"{folder} missing {missing}")

    catalog = CIRCUITS.get(folder, {})
    print(f"{folder}: {catalog.get('name', '(unmapped)')} in_game={catalog.get('in_game')}")

    scratch = args.scratch / f"track_{nn}"
    scratch.mkdir(parents=True, exist_ok=True)

    extra: list[str] = [f"--units-per-meter={args.units_per_meter}"]
    if not args.no_flip_z:
        extra.append("--flip-z")

    mesh_gltf = scratch / f"Track_{nn}_mesh.gltf"
    scene_gltf = scratch / f"Track_{nn}_scene.gltf"
    sky_gltf = scratch / f"Track_{nn}_sky.gltf"
    curve_json = scratch / f"track_{nn}_curve.json"
    flags_json = scratch / f"track_{nn}_face_flags.json"

    run_py(
        TOOLS_DIR / "convert_track_geometry.py",
        str(src / "TRACK.TRV"),
        str(src / "TRACK.TRF"),
        str(mesh_gltf),
        "--library-cmp",
        str(src / "LIBRARY.CMP"),
        "--library-ttf",
        str(src / "LIBRARY.TTF"),
        *extra,
    )
    run_py(TOOLS_DIR / "convert_track_sections.py", str(src / "TRACK.TRS"), str(curve_json), *extra)
    run_py(
        TOOLS_DIR / "convert_track_face_flags.py",
        str(src / "TRACK.TRV"),
        str(src / "TRACK.TRF"),
        str(flags_json),
        *extra,
    )
    run_py(TOOLS_DIR / "convert_track_scenery.py", str(src / "SCENE.PRM"), str(src / "SCENE.CMP"), str(scene_gltf), *extra)
    run_py(TOOLS_DIR / "convert_track_scenery.py", str(src / "SKY.PRM"), str(src / "SKY.CMP"), str(sky_gltf), *extra)

    glbs = {
        mesh_gltf: scratch / f"Track_{nn}_mesh.glb",
        scene_gltf: scratch / f"Track_{nn}_scene.glb",
        sky_gltf: scratch / f"Track_{nn}_sky.glb",
    }
    if not args.skip_blender:
        for gltf, glb in glbs.items():
            run_blender(gltf, glb)
    else:
        print("skip blender (--skip-blender)")

    dest_dir = args.godot_assets / f"Track_{nn}"
    if not args.skip_copy:
        dest_dir.mkdir(parents=True, exist_ok=True)
        copy_if_exists(curve_json, dest_dir / curve_json.name)
        copy_if_exists(flags_json, dest_dir / flags_json.name)
        if not args.skip_blender:
            for glb in glbs.values():
                copy_if_exists(glb, dest_dir / glb.name)
    else:
        print("skip copy (--skip-copy)")

    import json

    points = json.loads(curve_json.read_text(encoding="utf-8"))["points"]
    spawn_index = spawn_section_index(folder)
    if spawn_index >= len(points):
        print(f"WARNING: spawn index {spawn_index} >= npts {len(points)}; using 0")
        spawn_index = 0
    spawn_literal = yaw_only_transform(points, spawn_index, 2.0)
    print(f"ShipSpawn index={spawn_index} (start_line_pos-15)")
    print(spawn_literal)

    scene_path = GODOT_DIR / "src" / "scenes" / f"Track{nn}.tscn"
    if args.write_scene:
        if scene_path.exists() and not args.overwrite_scene:
            print(f"scene exists, not overwriting: {scene_path} (pass --overwrite-scene)")
        else:
            write_track_scene(nn, scene_path, spawn_literal)

    if args.godot_import:
        godot = args.godot_bin
        if not godot.is_file():
            raise SystemExit(f"Godot binary not found: {godot}")
        cmd = [str(godot), "--headless", "--path", str(GODOT_DIR / "src"), "--import"]
        print("+", " ".join(cmd))
        subprocess.run(cmd, check=True)

    print(f"done {folder} -> {dest_dir if not args.skip_copy else scratch}")


if __name__ == "__main__":
    main()
