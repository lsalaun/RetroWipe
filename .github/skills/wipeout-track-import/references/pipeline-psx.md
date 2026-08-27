# Pipeline A — full PSX TRACKNN import

Run converters from `godot/tools/psx_track/` unless noted. Pass **identical** `--flip-z` / `--units-per-meter` on every step. Track01 / Track02: no `--flip-z`.

Scratch: `_converted_tracks/track_NN/`. Deliverables: `godot/src/assets/tracks/Track_NN/`. Scene: `godot/src/scenes/TrackNN.tscn` (no underscore — `Track03.tscn`, not `Track_03.tscn`).

**Run** these commands (see [execution.md](./execution.md)); do not only print them.

## Source files (`wipeout/TRACKNN/`)

| File | Usage |
| --- | --- |
| `TRACK.TRV` | Vertices (BE) |
| `TRACK.TRF` | Faces / texture id / flags (BE) |
| `TRACK.TRS` | Sections, next/prev, jump/junction (BE) |
| `LIBRARY.CMP` + `LIBRARY.TTF` | Track textures (CMP LE TIM; TTF BE tile map) |
| `SCENE.PRM` + `SCENE.CMP` | Scenery |
| `SKY.PRM` + `SKY.CMP` | Sky dome |

`TRACK.INF` is tooling-only. Circuit name/class: `src/wipeout/game.c` `def.circuits`.

## 1. Textured track mesh

```powershell
py convert_track_geometry.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRV `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRF `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.gltf `
  --library-cmp D:\code\wipeout-rewrite\wipeout\TRACKNN\LIBRARY.CMP `
  --library-ttf D:\code\wipeout-rewrite\wipeout\TRACKNN\LIBRARY.TTF
```

Produces glTF + `.bin` + `Track_NN_mesh_textures/tex_*.png`. Without `--library-*`, looks next to the `.TRV` (case-insensitive). `--no-textures` skips PNG.

Log checks: in-range face indices, unit normals, coherent texture count. Upside-down or mirrored → rerun with `--flip-z` **and** apply it to every other converter.

## 2. AI center line

```powershell
py convert_track_sections.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRS `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\track_NN_curve.json
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
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\track_NN_face_flags.json
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
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_scene.gltf

py convert_track_scenery.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SKY.PRM `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SKY.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_sky.gltf
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
| `godot/tools/psx_track/convert_track_geometry.py` | TRV+TRF (+CMP/TTF) → textured glTF |
| `godot/tools/psx_track/convert_track_sections.py` | TRS → center-line JSON |
| `godot/tools/psx_track/convert_track_face_flags.py` | pickup/boost/start_grid JSON |
| `godot/tools/psx_track/convert_track_scenery.py` | SCENE/SKY PRM+CMP → glTF |
| `godot/tools/psx_track/psx_track_common.py` | Shared parsers, axes, scale |
| `godot/tools/blender/convert_track_mesh.py` | glTF+PNG → embedded GLB |
