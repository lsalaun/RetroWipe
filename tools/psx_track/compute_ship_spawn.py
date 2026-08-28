"""Prints a Godot .tscn Transform3D literal for ShipSpawn from a TRS curve JSON.

Yaw-only spawn (basis.y is always (0,1,0)): forward from consecutive centerline
XZ, origin.xz = point, origin.y = point.y + 2.0. Index is start_line_pos - 15
from src/wipeout/game.c (not curve point 0).

The .tscn Transform3D literal is row-major: given basis.x=(x1,x2,x3),
basis.y=(y1,y2,y3), basis.z=(z1,z2,z3) the order is
Transform3D(x1,y1,z1, x2,y2,z2, x3,y3,z3, ox,oy,oz).

Usage:
    py compute_ship_spawn.py track_01_curve.json --track TRACK01
    py compute_ship_spawn.py track_04_curve.json --index 1
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from circuit_catalog import CIRCUITS, HOVER_CLEARANCE_M, folder_key, spawn_section_index


def fmt(value: float) -> str:
    if abs(value) < 1e-12:
        return "0.000000000000"
    return f"{value:.12f}"


def yaw_only_transform(points: list[list[float]], index: int, hover: float) -> str:
    p = points[index]
    q = points[(index + 1) % len(points)]
    dx = q[0] - p[0]
    dz = q[2] - p[2]
    length = math.hypot(dx, dz)
    if length == 0.0:
        raise SystemExit(f"zero planar delta at index {index}")
    fx, fz = dx / length, dz / length
    zx, zy, zz = -fx, 0.0, -fz
    yx, yy, yz = 0.0, 1.0, 0.0
    # UP.cross(basis.z): (0,1,0) x (zx,0,zz) = (zz, 0, -zx)
    xx, xy, xz = zz, 0.0, -zx
    ox, oy, oz = p[0], p[1] + hover, p[2]
    return (
        f"Transform3D({fmt(xx)}, {fmt(yx)}, {fmt(zx)}, "
        f"{fmt(xy)}, {fmt(yy)}, {fmt(zy)}, "
        f"{fmt(xz)}, {fmt(yz)}, {fmt(zz)}, "
        f"{fmt(ox)}, {fmt(oy)}, {fmt(oz)})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("curve_json", type=Path, help="track_NN_curve.json from convert_track_sections.py")
    parser.add_argument("--track", help="TRACKNN folder name (looks up start_line_pos in circuit_catalog)")
    parser.add_argument("--index", type=int, default=None, help="Override spawn section index into the JSON points")
    parser.add_argument("--hover", type=float, default=HOVER_CLEARANCE_M, help=f"Y offset in meters (default {HOVER_CLEARANCE_M})")
    args = parser.parse_args()

    data = json.loads(args.curve_json.read_text(encoding="utf-8"))
    points = data["points"]
    if not points:
        raise SystemExit(f"no points in {args.curve_json}")

    if args.index is not None:
        index = args.index
    elif args.track:
        key = folder_key(args.track)
        if key not in CIRCUITS:
            raise SystemExit(f"unknown track {args.track!r}")
        index = spawn_section_index(key)
        info = CIRCUITS[key]
        print(f"{key}: {info['name']} start_line_pos={info['start_line_pos']} spawn_index={index}")
    else:
        raise SystemExit("pass --track TRACKNN or --index N")

    if not (0 <= index < len(points)):
        raise SystemExit(f"index {index} out of range (0..{len(points) - 1}), npts={len(points)}")

    literal = yaw_only_transform(points, index, args.hover)
    print(f"npts={len(points)} closed={data.get('closed')} index={index} hover={args.hover}")
    print(literal)


if __name__ == "__main__":
    main()
