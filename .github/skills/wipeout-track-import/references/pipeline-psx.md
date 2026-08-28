# Pipeline A — full PSX TRACKNN import

Run converters from `godot/tools/psx_track/` unless noted. **Default: `--flip-z` on every converter.** Pass identical `--flip-z` / `--units-per-meter` on geometry, sections, face flags, scenery, and sky. Omitting `--flip-z` is `(x,-y,z)` — a reflection vs wipeout-rewrite (L/R + ads mirrored).

Scratch: `_converted_tracks/track_NN/`. Deliverables: `godot/src/assets/tracks/Track_NN/`. Scene: `godot/src/scenes/TrackNN.tscn` (no underscore — `Track03.tscn`, not `Track_03.tscn`).

**Run** these commands (see [execution.md](./execution.md)); do not only print them.

## Default: orchestrator

Do **not** chain the five converters + Blender + copy by hand for a normal import. Run:

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py TRACKNN
```

That script:

1. Checks `wipeout/TRACKNN/` for `TRACK.TRV/TRF/TRS`, `LIBRARY.CMP/TTF`, `SCENE.PRM/CMP`, `SKY.PRM/CMP`.
2. Prints `circuit_catalog.py` name / `in_game` (`def.circuits`). TRACK15: `in_game=False`.
3. Writes scratch glTF/JSON under `_converted_tracks/track_NN/`.
4. Re-exports mesh / scene / sky → `.glb` via `godot/tools/blender/convert_track_mesh.py`.
5. Copies GLB + JSON into `godot/src/assets/tracks/Track_NN/` (same filename → UID kept).
6. Prints yaw-only `ShipSpawn` at index `start_line_pos - 15` (not point 0).

| Flag | Use |
| --- | --- |
| *(none)* | Convert + GLB + copy; **does not** write `TrackNN.tscn` |
| `--write-scene` | Write `godot/src/scenes/TrackNN.tscn` **only if missing** (no `ext_resource` UIDs) |
| `--overwrite-scene` | Required to clobber an existing `.tscn`. Do not use on Track01–14 unless the user asked. |
| `--godot-import` | `godot --headless --path godot/src --import` after copy |
| `--skip-blender` / `--skip-copy` | Parse debug; stop at glTF/JSON |
| `--no-flip-z` | Mirror diagnostic only — not a deliverable |
| `--units-per-meter` | Default `106.5`; pushed to every converter |
| `--godot-bin` | Override default `d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe` |

Spawn only (JSON already produced):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\compute_ship_spawn.py `
  D:\code\wipeout-rewrite\godot\src\assets\tracks\Track_01\track_01_curve.json `
  --track TRACK01
```

TRACK01 control: `index=12`, origin `(-356.807511737089, 3.164319248826, 299.417840375587)`, `basis.y = (0,1,0)`, no `-0.000…`.

### `start_line_pos` (`circuit_catalog.py`)

Godot spawn index = C `start_line_pos` − 15.

| TRACK | Name | Class | `start_line_pos` | Spawn index |
| --- | --- | --- | --- | --- |
| 01 | TERRAMAX | venom | 27 | 12 |
| 02 | ALTIMA VII | venom | 27 | 12 |
| 03 | ALTIMA VII RAPIER | rapier | 27 | 12 |
| 04 | KARBONIS V | venom | 16 | 1 |
| 05 | KARBONIS V RAPIER | rapier | 16 | 1 |
| 06 | TERRAMAX RAPIER | rapier | 27 | 12 |
| 07 | KORODERA RAPIER | rapier | 16 | 1 |
| 08 | ARRIDOS IV | venom | 16 | 1 |
| 09 | SILVERSTREAM | venom | 16 | 1 |
| 10 | FIRESTAR | venom | 27 | 12 |
| 11 | ARRIDOS IV RAPIER | rapier | 16 | 1 |
| 12 | KORODERA | venom | 16 | 1 |
| 13 | SILVERSTREAM RAPIER | rapier | 16 | 1 |
| 14 | FIRESTAR RAPIER | rapier | 27 | 12 |
| 15 | *(not in `def.circuits`)* | — | 27 (default) | 12 |

`TRACK.INF` `outName` is **not** authoritative (TRACK15 says `trak1`).

The numbered steps below are the **fallback** (debug one converter, or orchestrator unavailable). Prefer `import_track.py`.

## Source files (`wipeout/TRACKNN/`)

| File | Usage |
| --- | --- |
| `TRACK.TRV` | Vertices (BE) |
| `TRACK.TRF` | Faces / texture id / flags (BE) |
| `TRACK.TRS` | Sections, next/prev, jump/junction (BE) |
| `LIBRARY.CMP` + `LIBRARY.TTF` | Track textures (CMP LE TIM; TTF BE tile map) |
| `SCENE.PRM` + `SCENE.CMP` | Scenery |
| `SKY.PRM` + `SKY.CMP` | Sky dome |

`TRACK.INF` is tooling-only and **wrong** for TRACK15 (`outName = trak1`). Circuit name / class / `start_line_pos`: `circuit_catalog.py` (`src/wipeout/game.c` `def.circuits`).

## 1. Textured track mesh

```powershell
py convert_track_geometry.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRV `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRF `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.gltf `
  --library-cmp D:\code\wipeout-rewrite\wipeout\TRACKNN\LIBRARY.CMP `
  --library-ttf D:\code\wipeout-rewrite\wipeout\TRACKNN\LIBRARY.TTF `
  --flip-z
```

Produces glTF + `.bin` + `Track_NN_mesh_textures/tex_*.png`. Without `--library-*`, looks next to the `.TRV` (case-insensitive). `--no-textures` skips PNG.

Log checks: in-range face indices, unit normals, coherent texture count. Pipeline A **always** passes `--flip-z` (Y-only negate without it is a mirror).

## 2. AI center line

```powershell
py convert_track_sections.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRS `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\track_NN_curve.json `
  --flip-z
```

Walks `section.next` from `--start` (default 0) until loop. Junction branches ignored (single racing line for `track_center_line.gd`).

JSON:

```json
{
  "points": [[x, y, z], ...],
  "closed": true,
  "section_flags": [["jump"], [], ...],
  "source_object": "TRACK.TRS (section 0)"
}
```

If `closed=false`, try another `--start` or inspect junctions.

## 3. Gameplay face flags

```powershell
py convert_track_face_flags.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRV `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRF `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\track_NN_face_flags.json `
  --flip-z
```

Exports only:

- `FACE_PICKUP_LEFT` / `FACE_PICKUP_RIGHT` → `pickup_pads` (`side`: left/right)
- `FACE_BOOST` → `boost_pads`
- `FACE_START_GRID` → `start_grid`

Each entry: `face_index`, `center` (quad average, same space as mesh). TRACK01 has no `START_GRID` faces (original engine uses `start_line_pos`).

## 4. Scenery and sky

```powershell
py convert_track_scenery.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SCENE.PRM `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SCENE.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_scene.gltf `
  --flip-z

py convert_track_scenery.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SKY.PRM `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SKY.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_sky.gltf `
  --flip-z
```

PRM origins baked into vertices (one combined static mesh). Sprites / splines / lights are parsed for stream alignment but produce no geometry.

Parse checks: loop lands exactly at EOF; max texture index == CMP entry count − 1.

## 5. Blender glTF → standalone GLB

Python glTF references external PNGs. Re-export **each** of mesh / scene / sky (do not merge):

```powershell
blender --background --python D:\code\wipeout-rewrite\godot\tools\blender\convert_track_mesh.py -- `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.gltf `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.glb
```

Repeat for `Track_NN_scene.gltf` and `Track_NN_sky.gltf`. Godot collides only the track mesh.

## 6. Copy + Godot import

Copy in place (keep UID / `.import` on overwrite):

- `Track_NN_mesh.glb`
- `Track_NN_scene.glb`
- `Track_NN_sky.glb`
- `track_NN_curve.json`
- `track_NN_face_flags.json`

Then **before** writing new `.tscn` UIDs:

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

Read `uid="uid://..."` from `*.glb.import`.

## Tool map

| Tool | Role |
| --- | --- |
| `godot/tools/psx_track/import_track.py` | Orchestrator (Pipeline A default) |
| `godot/tools/psx_track/circuit_catalog.py` | TRACKNN → name / `start_line_pos` |
| `godot/tools/psx_track/compute_ship_spawn.py` | Row-major yaw-only `Transform3D` |
| `godot/tools/psx_track/convert_track_geometry.py` | TRV+TRF (+CMP/TTF) → textured glTF |
| `godot/tools/psx_track/convert_track_sections.py` | TRS → center-line JSON |
| `godot/tools/psx_track/convert_track_face_flags.py` | pickup/boost/start_grid JSON |
| `godot/tools/psx_track/convert_track_scenery.py` | SCENE/SKY PRM+CMP → glTF |
| `godot/tools/psx_track/psx_track_common.py` | Shared parsers, axes, scale |
| `godot/tools/blender/convert_track_mesh.py` | glTF+PNG → embedded GLB |
