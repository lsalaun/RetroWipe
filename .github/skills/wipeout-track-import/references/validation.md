# Headless inspect / validate

**Run** these validators yourself, **serially**, and let each `quit()`. Do not kill the process. Do not paste the commands as the deliverable.

All scripts: `godot/src/tools/*.gd`, `extends SceneTree` (or `MainLoop`). `extends Node` + `_ready()` fails: "doesn't inherit from SceneTree or MainLoop".

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src -s res://tools/<script>.gd
```

## Rules

- Script must call `quit()` itself. Headless stdout/stderr is fully buffered; killing the process drops `print` / `push_warning`.
- `_ready()` of children `add_child()`'d in `_initialize()` may not have run when `_initialize()` returns (e.g. CenterLine curve still null). Wait 2–3 `physics_frame`s (often 2nd `_physics_process`) before reading `_ready()` side effects.
- Never run two validators in parallel against the same project (shared runtime/input state).
- No screenshots **under `--headless`**: the dummy driver gives a null viewport texture. Use printed positions over several physics frames — or drop `--headless` (see below) when the check is genuinely visual.
- The dummy driver has no shader compiler. A `ShaderMaterial` reaching `set_surface_override_material()` logs `Parameter "material" is null` on every headless run; `track_sky.gd` skips its material swap when `DisplayServer.get_name() == "headless"` for that reason. If you add another shader-driven visual, guard it the same way rather than letting validators emit the error.
- `Node3D.to_global()` / global transforms can still fail inside `SceneTree._init()` even after `add_child()`. For temp imported scenes, rebuild world points from chained local `transform` or defer until fully in-tree.

## Windowed capture (the only way to check anything visual)

Drop `--headless`: the same `-s` script then opens a real window with the Vulkan
Forward+ renderer, and `root.get_texture().get_image().save_png(path)` works.
Used to validate the sky-dome fix (`docs/.transactional/26-09-01-01/tickets/`).

```gdscript
extends SceneTree

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 240:                      # let the track stream in and settle
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit(0)
	return false
```

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/<script>.gd -- C:\path\to\shot.png
```

For a camera tour of a circuit, instantiate `TrackNN.tscn` plus a `Camera3D`
matching `WipeoutShip.tscn` (`fov = 82`, `near = 0.05`, `far = 400`) and step it
along `CenterLine.curve`. Read the curve in `_process()`, **not**
`_initialize()`: `track_center_line.gd` fills it in `_ready()`.

Delete the temp script afterwards (and its `.uid`) — `src/tools/` is committed.

## inspect_scene.gd

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/inspect_scene.gd -- res://assets/tracks/Track_NN/Track_NN_mesh.glb
```

Expect MeshInstance3D, `surfaces > 0`, non-zero AABB. Empty node only → typical failed curve-as-glTF export.

## inspect_ai_track_alignment.gd

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/inspect_ai_track_alignment.gd
```

Loads `main.tscn`, waits one physics frame, prints for Ship / ShipAI1 / ShipAI2: position, curve offset, XZ lateral error, heading. Use after spawn rewire or new curve JSON.

## validate_track_side_walls.gd

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/validate_track_side_walls.gd
```

Hard-wired to **Track01**: ship on Track01.tscn; ground under spawn must not be classified as wall; push toward right shelf (~18 m); require bounce, not climb > 3.5 m. Safety net for trimesh + backface.

Other tracks: duplicate / parameterize `TRACK_SCENE` and lateral offset (lane width).

## validate_ai_field.gd

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/validate_ai_field.gd
```

48 physics frames on `main.tscn`: 8 ships (7 AI + 1 player), populated `center_line`, ≥5 AI moving, ranks 1–8 unique.

## setup_input_map.gd (not import, often forgotten)

Editing the `.gd` does **not** update `project.godot`. Must run:

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/setup_input_map.gd
```

## New-circuit checklist

1. Identify TRACKNN ↔ in-game name via `game.c` / `TRACK.INF`.
2. Convert geometry, sections, face flags, scene, sky with **`--flip-z`** and the same `--units-per-meter` on every converter.
3. Re-export 3 glTF → GLB via Blender headless.
4. Copy GLB + JSON into `godot/src/assets/tracks/Track_NN/` (same names on replace).
5. `--import` then read UIDs from `.import`.
6. Create/update `scenes/TrackNN.tscn` (`Track03.tscn`, not `Track_03.tscn`). Check the `Sky` node kept `track_sky.gd` + `sky_y_offset`.
7. Compute ShipSpawn (yaw-only at `start_line_pos - 15`, not JSON point 0, + 2 m if TRS curve; raycast if Blender curve).
8. Verify Transform3D (row-major, ≥12 decimals, `basis.y = (0,1,0)`).
9. `inspect_scene.gd` on GLBs; `inspect_ai_track_alignment.gd` once wired in `main.tscn`.
10. Adapt / rerun `validate_track_side_walls.gd` if the lane has edge shelves.
11. Rerun `validate_ai_field.gd` if this circuit becomes `main.tscn`'s track.
12. Windowed capture of the circuit (see above) if anything visual changed — sky, culling, alignment.
