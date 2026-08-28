"""Convert COMMON/ALLSH.PRM+CMP (and optional ALCOL) to Godot ship GLBs.

Usage:
    py godot/tools/psx_track/import_ships.py
    py godot/tools/psx_track/import_ships.py --collision
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from psx_track_common import DEFAULT_UNITS_PER_METER

TOOLS_DIR = Path(__file__).resolve().parent
GODOT_DIR = TOOLS_DIR.parent.parent
REPO_ROOT = GODOT_DIR.parent
BLENDER_CONVERT = GODOT_DIR / "tools" / "blender" / "convert_track_mesh.py"


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True, cwd=str(cwd) if cwd else None)


def convert_prm_dir(prm: Path, cmp: Path, scratch: Path, flip_z: bool, units: float) -> None:
    scratch.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable,
        str(TOOLS_DIR / "convert_ships.py"),
        str(prm),
        str(cmp),
        str(scratch),
        f"--units-per-meter={units}",
    ]
    if flip_z:
        cmd.append("--flip-z")
    run(cmd, cwd=TOOLS_DIR)


def gltf_to_glb(gltf: Path, glb: Path) -> None:
    run(["blender", "--background", "--python", str(BLENDER_CONVERT), "--", str(gltf), str(glb)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--common", type=Path, default=REPO_ROOT / "wipeout" / "COMMON")
    parser.add_argument("--scratch", type=Path, default=REPO_ROOT / "_converted_tracks" / "ships")
    parser.add_argument("--godot-ships", type=Path, default=GODOT_DIR / "src" / "assets" / "ships")
    parser.add_argument("--units-per-meter", type=float, default=DEFAULT_UNITS_PER_METER)
    parser.add_argument("--no-flip-z", action="store_true")
    parser.add_argument("--skip-blender", action="store_true")
    parser.add_argument("--skip-copy", action="store_true")
    parser.add_argument("--collision", action="store_true", help="Also convert ALCOL.PRM collision hulls")
    args = parser.parse_args()

    flip_z = not args.no_flip_z
    visual_prm = args.common / "ALLSH.PRM"
    visual_cmp = args.common / "ALLSH.CMP"
    if not visual_prm.is_file() or not visual_cmp.is_file():
        raise SystemExit(f"missing {visual_prm} or {visual_cmp}")

    convert_prm_dir(visual_prm, visual_cmp, args.scratch, flip_z, args.units_per_meter)

    gltfs = sorted(args.scratch.glob("*.gltf"))
    if not gltfs:
        raise SystemExit(f"no glTF produced in {args.scratch}")

    if not args.skip_blender:
        for gltf in gltfs:
            gltf_to_glb(gltf, gltf.with_suffix(".glb"))

    if not args.skip_copy and not args.skip_blender:
        args.godot_ships.mkdir(parents=True, exist_ok=True)
        for glb in sorted(args.scratch.glob("*.glb")):
            dest_dir = args.godot_ships / glb.stem
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / glb.name
            shutil.copy2(glb, dest)
            print(f"copied {glb.name} -> {dest}")

    if args.collision:
        col_scratch = args.scratch.parent / "ship_collision"
        convert_prm_dir(args.common / "ALCOL.PRM", args.common / "ALCOL.CMP", col_scratch, flip_z, args.units_per_meter)
        if not args.skip_blender:
            for gltf in sorted(col_scratch.glob("*.gltf")):
                gltf_to_glb(gltf, gltf.with_suffix(".glb"))
        print(f"collision hulls in {col_scratch} (not copied; Godot still uses box hulls)")

    print("done ships")


if __name__ == "__main__":
    main()
