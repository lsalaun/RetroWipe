"""Converts the original PSX WipEout track topology (TRACK.TRS) into the
JSON format expected by track_center_line.gd (Godot side), producing the
AI racing-line centerline directly from the real section->center chain that
ship_ai.c follows (see ship_ai_update_race()), instead of a hand-authored
Blender curve.

Standalone parser (stdlib only, no Blender/bpy required). Mirrors the binary
layout read by track_load_sections() in wipeout-rewrite's src/wipeout/track.c:

    TRACK.TRS: 156 bytes/section, big-endian (see convert_track_geometry.py's
    module docstring for why), containing:
        int32 junction (section index, or -1 if none)
        int32 prev, int32 next (section indices)
        int32 center.x, center.y, center.z
        int16 version (must be TRACK_VERSION=8 in the original engine; only
               logged here, not enforced, since older/other tracks may differ)
        ... engine-internal fields (object/view/LOD lists) skipped ...
        int16 face_start, int16 face_count
        ... radius fields skipped ...
        int16 flags (SECTION_JUMP=1, SECTION_JUNCTION_END=8,
               SECTION_JUNCTION_START=16, SECTION_JUNCTION=32)
        int16 num

The main loop is reconstructed by walking `next` starting from --start
(default section 0) until it loops back to the start (closed track) or runs
out of unvisited sections (open path) -- this ignores `junction` branches,
matching the single main racing line already consumed by
track_center_line.gd. Section flags are exported alongside the points (a
track_center_line.gd extension point for later: SECTION_JUMP/junction-aware
rescue logic is currently out of scope, see docs/.transactional/26-08-24-02
/audit/physique_vaisseau_audit.md).

Usage:
    python convert_track_sections.py TRACK.TRS output.json
    python convert_track_sections.py TRACK.TRS output.json --start 0 --flip-z
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path

from psx_track_common import make_axis_transform

SECTION_STRUCT = struct.Struct(
    ">"
    "i"    # junction section index (-1 = none)
    "i"    # prev section index
    "i"    # next section index
    "iii"  # center x, y, z
    "h"    # version
    "2x"   # padding
    "8x"   # objects pointer + object count
    "60x"  # view section pointers (5*3*4)
    "30x"  # view section counts (5*3*2)
    "8x"   # high list
    "8x"   # med list
    "h"    # face_start
    "h"    # face_count
    "4x"   # global/local radius
    "h"    # flags
    "h"    # num
    "2x"   # padding
)

SECTION_JUMP = 1
SECTION_JUNCTION_END = 8
SECTION_JUNCTION_START = 16
SECTION_JUNCTION = 32

FLAG_NAMES = {
    SECTION_JUMP: "jump",
    SECTION_JUNCTION_END: "junction_end",
    SECTION_JUNCTION_START: "junction_start",
    SECTION_JUNCTION: "junction",
}


@dataclass
class Section:
    junction: int
    prev: int
    next: int
    center: tuple[float, float, float]
    version: int
    face_start: int
    face_count: int
    flags: int
    num: int


def parse_trs(path: Path) -> list[Section]:
    data = path.read_bytes()
    count = len(data) // SECTION_STRUCT.size
    sections = []
    for i in range(count):
        junction, prev, next_, cx, cy, cz, version, face_start, face_count, flags, num = (
            SECTION_STRUCT.unpack_from(data, i * SECTION_STRUCT.size)
        )
        sections.append(Section(junction, prev, next_, (cx, cy, cz), version, face_start, face_count, flags, num))
    return sections


def decode_flags(flags: int) -> list[str]:
    return [name for bit, name in FLAG_NAMES.items() if flags & bit]


def walk_main_loop(sections: list[Section], start: int) -> tuple[list[int], bool]:
    """Follows `next` from `start` until it loops back (closed) or dead-ends."""
    order = []
    visited = set()
    index = start
    while index not in visited and 0 <= index < len(sections):
        visited.add(index)
        order.append(index)
        index = sections[index].next

    closed = index == start
    return order, closed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("trs", type=Path, help="Path to TRACK.TRS")
    parser.add_argument("output", type=Path, help="Output JSON path (consumed by track_center_line.gd)")
    parser.add_argument("--start", type=int, default=0, help="Section index to start the loop from (default 0)")
    parser.add_argument(
        "--flip-z", action="store_true",
        help="Also negate Z, keep in sync with convert_track_geometry.py's --flip-z for this same track",
    )
    args = parser.parse_args()

    sections = parse_trs(args.trs)
    if not sections:
        raise SystemExit(f"No sections parsed from {args.trs}")
    if not (0 <= args.start < len(sections)):
        raise SystemExit(f"--start {args.start} out of range (0..{len(sections) - 1})")

    order, closed = walk_main_loop(sections, args.start)

    transform, _ = make_axis_transform(args.flip_z)
    points = [list(transform(sections[i].center)) for i in order]
    section_flags = [decode_flags(sections[i].flags) for i in order]

    data = {
        "points": points,
        "closed": closed,
        "section_flags": section_flags,
        "source_object": f"{args.trs.name} (section {args.start})",
    }
    args.output.write_text(json.dumps(data), encoding="utf-8")

    jump_count = sum(1 for f in section_flags if "jump" in f)
    print(
        f"Parsed {len(sections)} sections, walked {len(order)} of them "
        f"(closed={closed}, {jump_count} jump section(s)). Wrote {args.output}"
    )
    if not closed:
        print(
            "WARNING: loop did not return to --start; the track may use a "
            "different start section, or main-line traversal hit a junction "
            "quirk. Inspect the output or try a different --start."
        )


if __name__ == "__main__":
    main()
