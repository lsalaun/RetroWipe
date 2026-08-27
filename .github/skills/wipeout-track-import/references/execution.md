# Execution contract

This skill **runs** the import. Pasting a command list for the user is a failure unless a step cannot run (missing `wipeout/TRACKNN/` files, Blender/Godot binary missing, interactive elevation).

## Do

1. Resolve `TRACKNN` → scratch `track_NN` → assets `Track_NN` → scene `TrackNN.tscn` using the naming table in `SKILL.md`.
2. Verify source files exist (`TRACK.TRV`/`TRF`/`TRS`, `LIBRARY.CMP`/`TTF`, `SCENE.*`, `SKY.*`) with `Test-Path` / `list_dir` before converting.
3. Create `_converted_tracks/track_NN/` if needed.
4. Run converters from `godot/tools/psx_track/` with `py` (cwd that directory, or pass absolute script paths). **Always pass `--flip-z`** on geometry, sections, face flags, scenery, and sky. Use PowerShell; chain with `;` never `&&`.
5. Run steps **serially**. Do not parallelize two Godot `--headless` jobs on `godot/src`. Python converts may be sequential too (shared scratch).
6. After each convert, check exit code **and** log: in-range indices, `closed: true`, scenery parse at EOF, max texture index == CMP count − 1.
7. Run Blender three times (mesh, scene, sky). Confirm each `.glb` exists and is non-tiny before copy.
8. Copy deliverables into `godot/src/assets/tracks/Track_NN/` (create dir on first import; overwrite in place on re-import).
9. Run Godot `--import`, then `read_file` the `*.glb.import` UID lines (do not guess UIDs; `grep` can miss fresh `.import` files).
10. Write `TrackNN.tscn`. Compute ShipSpawn via a short Godot or Python probe that prints ≥12 invariant decimals; paste that literal. First reproduce Track01 spawn from Track01's curve JSON.
11. Run `inspect_scene.gd` on the new GLBs. Run other validators only when applicable (alignment / AI field need the circuit in `main.tscn`; side walls are Track01-hardwired unless parameterized).
12. Leave validators to `quit()`; never `kill_terminal` a headless Godot job.

## Godot / Python binaries

```powershell
$godot = "d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe"
# python: py
# blender: blender
```

`--path` for Godot is always `D:\code\wipeout-rewrite\godot\src` (the Godot project), not the git workspace `godot/` folder.

Around native Godot, if the harness uses `$ErrorActionPreference = 'Stop'`, set it to `Continue` for that invocation and still honor `$LASTEXITCODE`.

## Stop and report (do not improvise)

- Converter `IndexError` / index `65280` → endian mix; fix invocation, do not patch indices.
- Curve glTF empty / AABB zero on a “curve” GLB → you used the wrong exporter; switch to JSON.
- `closed: false` → try `--start` or inspect junctions before wiring CenterLine.
- Visual mirror → you omitted `--flip-z` on at least one converter. Rerun **all** converters with `--flip-z`; do not invent another axis. Still mirrored **with** `--flip-z` on every step → stop and report, do not improvise.
- Basis / `get_rotation_quaternion` errors → row-major literal or over-rounding; recompute, do not tweak digits by eye.

## PowerShell notes

- Locale: invariant decimal point when printing transforms.
- `py` not `python`.
- Do not poll `Start-Sleep` on Godot; use sync runs and scripts that `quit()`.
