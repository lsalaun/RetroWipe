"""Extracts gameplay-relevant face flags from TRACK.TRF (weapon pickup pads,
boost pads, start grid) into a JSON file, for placing gameplay triggers in
Godot without having to re-parse the raw PSX geometry format.

Mirrors the flags read by track_load_faces() in wipeout-rewrite's
src/wipeout/track.c (see track.h):
    FACE_PICKUP_LEFT  (1<<1) / FACE_PICKUP_RIGHT (1<<3) -- weapon pickup pads
    FACE_BOOST        (1<<5)                            -- speed boost pads
    FACE_START_GRID   (1<<4)                             -- starting grid

FACE_TRACK_BASE/FACE_FLIP_TEXTURE/FACE_PICKUP_COLLECTED/FACE_PICKUP_ACTIVE
are not exported: the first two aren't gameplay triggers, and the last two
are runtime state (set/cleared by track_cycle_pickups() at play time), not
static track data.

Each flagged face is reported with its quad center (average of its 4
vertices), using the exact same axis flip/scale conventions as
convert_track_geometry.py (--flip-z/--units-per-meter must match the
geometry export for the same track so positions line up).

Usage:
    python convert_track_face_flags.py TRACK.TRV TRACK.TRF output.json
    python convert_track_face_flags.py TRACK.TRV TRACK.TRF output.json --flip-z
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from psx_track_common import (
    DEFAULT_UNITS_PER_METER,
    FACE_BOOST,
    FACE_PICKUP_LEFT,
    FACE_PICKUP_RIGHT,
    FACE_START_GRID,
    Face,
    make_axis_transform,
    parse_trf,
    parse_trv,
    scale_point,
)


def face_center(
    face: Face,
    vertices: list[tuple[float, float, float]],
    transform,
    units_per_meter: float,
) -> list[float]:
    points = [scale_point(transform(vertices[i]), units_per_meter) for i in face.indices]
    x = sum(p[0] for p in points) / len(points)
    y = sum(p[1] for p in points) / len(points)
    z = sum(p[2] for p in points) / len(points)
    return [x, y, z]


def extract_face_flags(
    vertices: list[tuple[float, float, float]],
    faces: list[Face],
    flip_z: bool,
    units_per_meter: float,
) -> dict[str, list[dict]]:
    transform, _ = make_axis_transform(flip_z)

    pickup_pads: list[dict] = []
    boost_pads: list[dict] = []
    start_grid: list[dict] = []

    for i, face in enumerate(faces):
        center = None  # computed lazily, only if this face has a flag we care about

        if face.flags & FACE_PICKUP_LEFT:
            center = center or face_center(face, vertices, transform, units_per_meter)
            pickup_pads.append({"face_index": i, "side": "left", "center": center})
        if face.flags & FACE_PICKUP_RIGHT:
            center = center or face_center(face, vertices, transform, units_per_meter)
            pickup_pads.append({"face_index": i, "side": "right", "center": center})
        if face.flags & FACE_BOOST:
            center = center or face_center(face, vertices, transform, units_per_meter)
            boost_pads.append({"face_index": i, "center": center})
        if face.flags & FACE_START_GRID:
            center = center or face_center(face, vertices, transform, units_per_meter)
            start_grid.append({"face_index": i, "center": center})

    return {"pickup_pads": pickup_pads, "boost_pads": boost_pads, "start_grid": start_grid}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("trv", type=Path, help="Path to TRACK.TRV")
    parser.add_argument("trf", type=Path, help="Path to TRACK.TRF")
    parser.add_argument("output", type=Path, help="Output JSON path")
    parser.add_argument(
        "--flip-z", action="store_true",
        help="Also negate Z, keep in sync with convert_track_geometry.py for this same track",
    )
    parser.add_argument(
        "--units-per-meter", type=float, default=DEFAULT_UNITS_PER_METER,
        help=f"Raw PSX units per meter (default {DEFAULT_UNITS_PER_METER}). Keep in sync with convert_track_geometry.py for this same track.",
    )
    args = parser.parse_args()

    vertices = parse_trv(args.trv)
    faces = parse_trf(args.trf)
    result = extract_face_flags(vertices, faces, args.flip_z, args.units_per_meter)

    args.output.write_text(json.dumps(result), encoding="utf-8")
    print(
        f"Parsed {len(faces)} faces -> {len(result['pickup_pads'])} pickup pad(s), "
        f"{len(result['boost_pads'])} boost pad(s), {len(result['start_grid'])} start grid face(s). "
        f"Wrote {args.output}"
    )


if __name__ == "__main__":
    main()
