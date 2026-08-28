---
name: wipeout-track-import
description: "Import a Wipeout PSX circuit into the Godot port via import_track.py (TRACK.TRV/TRF/TRS, LIBRARY.CMP/TTF, SCENE/SKY PRM+CMP → GLB, curve JSON, face flags, TrackNN.tscn, ShipSpawn at start_line_pos-15, headless validation). Use when: importing a track, converting TRACKNN, PSX→Godot pipeline, import_track.py, circuit_catalog, compute_ship_spawn, convert_track_geometry/sections/scenery/face_flags, Blender convert_track_mesh, export_track_curve, CenterLine, GameplayZones, inspect_scene, validate_track_side_walls, validate_ai_field."
argument-hint: TRACKNN or circuit name (e.g. TRACK03, Altima)
---

# Wipeout track import (PSX → Godot)

Specialist workflow for bringing a PSX circuit into this Godot port. **Execute** the pipeline (Python, Blender, Godot headless, file copy, scene write, validators). Do not dump commands for the user to run unless a step is blocked (missing disc data, UAC, missing binary). Do not improvise converters, axis flips, spawn math, or `.tscn` `Transform3D` literals.

Canonical long-form docs:

- `docs/.transactional/26-08-27-01/documentation/workflow_import_circuit.md`
- `docs/.transactional/26-08-27-01/documentation/workflow_import_track_orchestrator.md` (`import_track.py`)

Ships / TIM / SFX / COMMON weapons are **out of scope**. See `workflow_assets_overview.md` — do not stretch this skill to those dumps.

Execution protocol: [execution.md](./references/execution.md).

## When to use

- New `TRACKNN` import (mesh + racing line + flags + scenery + sky), typically TRACK15
- Re-import / overwrite of an existing `Track_NN` asset set (TRACK01–14 already in Godot)
- Track12-style racing line from a Blender curve (not `TRACK.TRS`)
- Wiring `TrackNN.tscn`, `ShipSpawn`, UIDs after `--import`
- Headless inspect/validate after a circuit is in the project

Do **not** use for ships (`ALLSH`), HUD TIM, audio, COMMON weapons, menus, or input-map work except the note that `setup_input_map.gd` must be *run*, not only edited.

TRACK01–TRACK14 assets and scenes already exist. Prefer regenerating via the orchestrator over rewriting `.tscn` by hand. TRACK15 is **not** in `def.circuits` (`TRACK.INF` `outName = trak1` is a tooling leftover).

## Naming (locked)

PSX folder `TRACK03` maps as follows (match Track01 / Track02 already in the repo):

| Thing | Pattern | Example |
| --- | --- | --- |
| PSX source | `wipeout/TRACKNN/` | `wipeout/TRACK03/` |
| Scratch | `_converted_tracks/track_NN/` | `_converted_tracks/track_03/` |
| Godot asset dir | `godot/src/assets/tracks/Track_NN/` | `Track_03/` |
| Asset files | `Track_NN_mesh.glb`, `track_NN_curve.json`, … | `Track_03_mesh.glb` |
| Scene file / root | `godot/src/scenes/TrackNN.tscn` | `Track03.tscn` (no underscore) |

Do not invent `Track03/` under assets or `Track_03.tscn` under scenes.

## Machine / path conventions

Paths below are relative to the **wipeout-rewrite repo root** (`d:\code\wipeout-rewrite`), not the Godot workspace root, unless they start with `godot/`.

| Role | This machine |
| --- | --- |
| Python | `py` (not `python` / `python3`) |
| Blender | `blender` (5.1 at `F:\Blender 5.1\blender.exe`) |
| Godot headless | `d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe` if `godot4` is not on PATH |
| Scratch | `_converted_tracks/track_NN/` |
| Godot assets | `godot/src/assets/tracks/Track_NN/` |
| Scenes | `godot/src/scenes/TrackNN.tscn` (reference: Track01 / Track02) |

C parsers live **outside** this workspace (`wipeout-rewrite/src/wipeout/`). `grep_search` will not find them; use absolute `read_file` or GitHub raw at the local commit hash.

Scripts in `godot/tools/psx_track/` resolve the repo root from their own path; they may be launched from any cwd.

## Decision tree

```text
Need a Godot circuit from PSX TRACKNN?
├─ Racing line from TRACK.TRS?  → Pipeline A. Default: import_track.py. See ./references/pipeline-psx.md
├─ Racing line from a .blend Curve? → Pipeline B for the curve only. See ./references/pipeline-blender-curve.md
└─ Scene already has GLB+JSON? → Skip convert; wire + validate. See ./references/scene-wiring.md and ./references/validation.md
```

**Default Pipeline A:** run `godot/tools/psx_track/import_track.py TRACKNN`. It always passes `--flip-z` (unless `--no-flip-z`) and the same `--units-per-meter` to geometry, sections, face flags, scenery, and sky. Manual per-converter commands are fallback only (debug parse, `--skip-blender`).

`--no-flip-z` yields `(x,-y,z)` — a reflection (L/R swapped, ads backwards vs wipeout-rewrite). Do not use it for a deliverable. Default scale is `DEFAULT_UNITS_PER_METER = 106.5` in `godot/tools/psx_track/psx_track_common.py`.

Identify the circuit with `circuit_catalog.py` (`def.circuits`), **not** `TRACK.INF` `outName`. TRACK15 is `in_game=False`.

## Hard rules (do not violate)

1. Converters are in `godot/tools/`, **not** `godot/src/tools/`. `src/tools` only inspects/validates (`extends SceneTree`, Godot `-s`).
2. **Endianness is mixed.** TRV/TRF/TRS, TTF, PRM = big-endian. CMP headers + TIM = little-endian. Symptom of mix-up: `IndexError` on a sub-tile index like `65280`.
3. **Always pass `--flip-z`** on geometry, sections, face flags, scenery, and sky. Do not treat it as optional or track-specific. Do not invent extra axis hacks if the mesh still looks wrong.
4. **Never export a Blender Curve via glTF.** Zero bevel/extrude → empty Node3D; Godot gets no Path3D. Use `export_track_curve.py` → JSON.
5. Colliders: trimesh (`create_trimesh_shape`) + `shape.backface_collision = true` on **TrackMesh only**. Convex hulls inflate into the lane.
6. `.tscn` `Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` is **row-major**. If `basis.x=(x1,x2,x3)` etc., write `Transform3D(x1,y1,z1, x2,y2,z2, x3,y3,z3, ox,oy,oz)`. Consecutive column triples = transpose ≈ 90° heading error. Emit ≥12 invariant decimals; never round to 5 dp (Basis must stay normalized). `|v| < 1e-12` → print `0.000000000000` (no `-0`).
7. After copying new `.glb`, run Godot `--import` **before** writing `ext_resource` UIDs. Stale UID in `.tscn` still resolves the old asset even if `path=` was updated. Read `uid://` from `*.glb.import`. `--write-scene` emits **no** UIDs; fill them after import.
8. Headless validators must `quit()` themselves (stdout is fully buffered). Do not kill the process. Do not run two validators in parallel on the same project. Reads that depend on `_ready()` (e.g. `CenterLine.curve`) wait 2–3 `physics_frame`s; `_initialize()` is too early. Scripts must `extends SceneTree`, not `Node`.
9. Overwrite GLB/JSON deliverables **in place** (same filename) so existing UID / `.import` files stay valid. Do **not** pass `--overwrite-scene` on Track01–14 unless the user explicitly asked to rewrite the `.tscn`.
10. `ShipSpawn` index is `start_line_pos - 15` from `circuit_catalog.py` / `game.c`, **not** JSON point 0. Print the literal with `compute_ship_spawn.py` (or the orchestrator stdout). First reproduce Track01's published transform from *its* JSON (`index=12`) before trusting a new track.

Full gotcha list: [gotchas.md](./references/gotchas.md).

## Procedure — Pipeline A (complete TRACKNN)

Work dir: `_converted_tracks/track_NN/`. Default path: [pipeline-psx.md](./references/pipeline-psx.md), [execution.md](./references/execution.md).

1. Map `TRACKNN` via `circuit_catalog.py` (name / class / `start_line_pos` / `in_game`). Ignore `TRACK.INF` `outName`.
2. Run the orchestrator (creates scratch, converts, Blender GLB, copy in place, prints `ShipSpawn`):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py TRACKNN
```

3. For a **new** scene only (file must not exist, or user asked to clobber): add `--write-scene`. Existing Track01–14: omit it. Clobber requires `--overwrite-scene`.
4. After copy of new GLBs: `--godot-import` or a separate `godot --headless --path godot/src --import`. Read UIDs from `*.glb.import` with `read_file`.
5. If `--write-scene` ran, patch `ext_resource` UIDs into `TrackNN.tscn`. Otherwise update an existing scene from Track01/Track02. [scene-wiring.md](./references/scene-wiring.md).
6. Confirm `ShipSpawn` against orchestrator stdout / `compute_ship_spawn.py --track TRACKNN`. Yaw-only; origin XZ = p.xz; **Y = p.y + 2.0** only for TRS curves; `basis.y = (0,1,0)`.
7. Run validators serially. [validation.md](./references/validation.md).

Orchestrator flags: `--skip-blender`, `--skip-copy` (parse debug), `--no-flip-z` (mirror diagnostic only), `--units-per-meter`, `--godot-bin`, `--scratch`.

Manual converters (`convert_track_geometry.py` etc.) remain valid fallbacks; do not invent a sixth axis convention.

## Procedure — Pipeline B (Blender racing line)

When the AI line is **not** from `TRACK.TRS` (Track12 pattern). [pipeline-blender-curve.md](./references/pipeline-blender-curve.md).

- `blender --background <curve.blend> --python godot/tools/blender/export_track_curve.py -- <out.json> 16`
- Axes: Blender Z-up → Godot `(x, z, -y)`. Supports BEZIER (sampled) and POLY (raw points).
- `ShipSpawn.y` is **not** `p0.y + 2`. Raycast / measure against the mesh (Track12 ≈ +3.14 m with curve y = 0).

## Expected scene tree

```text
TrackNN (Node3D + TrackMeshCollider)
├── TrackMesh       instance Track_NN_mesh.glb
├── Scenery         instance Track_NN_scene.glb   (visual only)
├── Sky             instance Track_NN_sky.glb     (visual only)
├── CenterLine      Path3D + track_center_line.gd
│                   source_json = res://assets/tracks/Track_NN/track_NN_curve.json
├── GameplayZones   Node3D + track_gameplay_zones.gd
│                   source_json = res://assets/tracks/Track_NN/track_NN_face_flags.json
└── ShipSpawn       Marker3D
```Orchestrator (or equivalent) used `--flip-z` **and** the same `--units-per-meter` on all converters
- [ ] Three separate GLBs (mesh / scene / sky), not one combined file
- [ ] Curve JSON `closed: true` (or documented why not); not an empty glTF curve
- [ ] Assets in `godot/src/assets/tracks/Track_NN/` with matching `.import` UIDs in the `.tscn`
- [ ] Scene tree matches Track01/Track02; collider only on TrackMesh; trimesh + backface
- [ ] `ShipSpawn` at `start_line_pos - 15`, yaw-only, `basis.y = (0,1,0)`, row-major literal, ≥12 decimals
- [ ] Existing Track01–14 `.tscn` not overwritten unless the user asked
- [ ] `inspect_scene.gd` on GLBs: MeshInstance3D, surfaces > 0, non-zero AABB
- [ ] After wiring into `main.tscn`: alignment inspect; side-wall validator if edge shelves; `validate_ai_field.gd` if this is the race track

## Known out of scope (do not "fix" during import)

Section `jump`/junction flags unused in Godot; weapon pads are markers only; boost is a one-shot Area3D impulse; no per-circuit `sky_y_offset`; scenery/sky have no collider and no auto `CULL_DISABLED`; PRM billboards/lights/splines parsed not meshed; scale 106.5 is an estimate (~3.2× vs elevation cross-check, unresolved). Headless cannot screenshot (`get_viewport().get_texture()` is null).

Not this skill: `ALLSH`/`ALCOL`, `wipeout/TEXTURES`, `WIPEOUT.VB` / music MP3, COMMON weapons/droid/menu (`import_ships.py`, `convert_textures.py`, `import_audio.py`, `convert_common.py`
- [ ] `inspect_scene.gd` on GLBs: MeshInstance3D, surfaces > 0, non-zero AABB
- [ ] After wiring into `main.tscn`: alignment inspect; side-wall validator if edge shelves; `validate_ai_field.gd` if this is the race track

## Known out of scope (do not "fix" during import)

Section `jump`/junction flags unused in Godot; weapon pads are markers only; boost is a one-shot Area3D impulse; no per-circuit `sky_y_offset`; scenery/sky have no collider and no auto `CULL_DISABLED`; PRM billboards/lights/splines parsed not meshed; scale 106.5 is an estimate (~3.2× vs elevation cross-check, unresolved). Headless cannot screenshot (`get_viewport().get_texture()` is null).
