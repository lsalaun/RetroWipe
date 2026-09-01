"""Wipeout (PSX) circuit / start-line catalog from src/wipeout/game.c def.circuits.

Used by import_track.py so ShipSpawn is derived at start_line_pos - 15, not
curve point 0. TRACK15 is a tooling leftover (TRACK.INF outName = trak1) and
is not in def.circuits.
"""

from __future__ import annotations

# track_folder -> {name, class, start_line_pos, circuit, sky_y_offset}
# start_line_pos is the C value; Godot spawn index = start_line_pos - 15.
# sky_y_offset is the C value too: raw PSX units, Y pointing down. TRACK15 is
# not in def.circuits, so it gets the neutral 0.
CIRCUITS: dict[str, dict] = {
    "TRACK01": {
        "name": "TERRAMAX",
        "race_class": "venom",
        "circuit": "TERRAMAX",
        "start_line_pos": 27,
        "sky_y_offset": -820,
        "in_game": True,
    },
    "TRACK02": {
        "name": "ALTIMA VII",
        "race_class": "venom",
        "circuit": "ALTIMA VII",
        "start_line_pos": 27,
        "sky_y_offset": -2520,
        "in_game": True,
    },
    "TRACK03": {
        "name": "ALTIMA VII RAPIER",
        "race_class": "rapier",
        "circuit": "ALTIMA VII",
        "start_line_pos": 27,
        "sky_y_offset": -1930,
        "in_game": True,
    },
    "TRACK04": {
        "name": "KARBONIS V",
        "race_class": "venom",
        "circuit": "KARBONIS V",
        "start_line_pos": 16,
        "sky_y_offset": -5000,
        "in_game": True,
    },
    "TRACK05": {
        "name": "KARBONIS V RAPIER",
        "race_class": "rapier",
        "circuit": "KARBONIS V",
        "start_line_pos": 16,
        "sky_y_offset": -5000,
        "in_game": True,
    },
    "TRACK06": {
        "name": "TERRAMAX RAPIER",
        "race_class": "rapier",
        "circuit": "TERRAMAX",
        "start_line_pos": 27,
        "sky_y_offset": 0,
        "in_game": True,
    },
    "TRACK07": {
        "name": "KORODERA RAPIER",
        "race_class": "rapier",
        "circuit": "KORODERA",
        "start_line_pos": 16,
        "sky_y_offset": -2260,
        "in_game": True,
    },
    "TRACK08": {
        "name": "ARRIDOS IV",
        "race_class": "venom",
        "circuit": "ARRIDOS IV",
        "start_line_pos": 16,
        "sky_y_offset": -40,
        "in_game": True,
    },
    "TRACK09": {
        "name": "SILVERSTREAM",
        "race_class": "venom",
        "circuit": "SILVERSTREAM",
        "start_line_pos": 16,
        "sky_y_offset": -2700,
        "in_game": True,
    },
    "TRACK10": {
        "name": "FIRESTAR",
        "race_class": "venom",
        "circuit": "FIRESTAR",
        "start_line_pos": 27,
        "sky_y_offset": 0,
        "in_game": True,
    },
    "TRACK11": {
        "name": "ARRIDOS IV RAPIER",
        "race_class": "rapier",
        "circuit": "ARRIDOS IV",
        "start_line_pos": 16,
        "sky_y_offset": -240,
        "in_game": True,
    },
    "TRACK12": {
        "name": "KORODERA",
        "race_class": "venom",
        "circuit": "KORODERA",
        "start_line_pos": 16,
        "sky_y_offset": -2120,
        "in_game": True,
    },
    "TRACK13": {
        "name": "SILVERSTREAM RAPIER",
        "race_class": "rapier",
        "circuit": "SILVERSTREAM",
        "start_line_pos": 16,
        "sky_y_offset": -2700,
        "in_game": True,
    },
    "TRACK14": {
        "name": "FIRESTAR RAPIER",
        "race_class": "rapier",
        "circuit": "FIRESTAR",
        "start_line_pos": 27,
        "sky_y_offset": 0,
        "in_game": True,
    },
    "TRACK15": {
        "name": "TRACK15 (test / unused)",
        "race_class": None,
        "circuit": None,
        "start_line_pos": 27,
        "sky_y_offset": 0,
        "in_game": False,
    },
}

SPAWN_SECTION_OFFSET = 15
HOVER_CLEARANCE_M = 2.0


def folder_key(name: str) -> str:
    return name.strip().upper()


def spawn_section_index(track_folder: str, start_line_pos: int | None = None) -> int:
    info = CIRCUITS.get(folder_key(track_folder), {})
    pos = start_line_pos if start_line_pos is not None else int(info.get("start_line_pos", 27))
    return pos - SPAWN_SECTION_OFFSET


def sky_y_offset_meters(track_folder: str, units_per_meter: float) -> float:
    """Height of the SKY.PRM dome above the camera, in Godot metres.

    The C `sky_y_offset` is in raw PSX units on a downward Y axis, so it is
    negated like every other imported position before being scaled.
    """
    info = CIRCUITS.get(folder_key(track_folder), {})
    return round(-int(info.get("sky_y_offset", 0)) / units_per_meter, 4)


def in_game_tracks() -> list[str]:
    return [key for key, info in CIRCUITS.items() if info.get("in_game")]
