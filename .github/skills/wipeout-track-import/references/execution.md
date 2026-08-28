# Execution contract

This skill **runs** the import. Pasting a command list for the user is a failure unless a step cannot run (missing `wipeout/TRACKNN/` files, Blender/Godot binary missing, interactive elevation).

## Do

1. Resolve `TRACKNN` → scratch `track_NN` → assets `Track_NN` → scene `TrackNN.tscn` using the naming table in `SKILL.md`. Look up name / spawn index in `circuit_catalog.py`, not `TRACK.INF`.
2. Verify source files exist (`TRACK.TRV`/`TRF`/`TRS`, `LIBRARY.CMP`/`TTF`, `SCENE.*`, `SKY.*`) with `Test-Path` / `list_dir` before converting.
3. **Default:** `py godot/tools/psx_track/import_track.py TRACKNN` (absolute path is fine; script finds repo root). It creates scratch, passes `--flip-z` + the same `--units-per-meter`, runs Blender, copies in place, prints `ShipSpawn`. Do not pass `--overwrite-scene` on Track01–14 unless the user asked. `--write-scene` only for a missing `TrackNN.tscn`.
4. Fallback (debug one converter): run scripts from `godot/tools/psx_track/` with `py`. **Always pass `--flip-z`** on geometry, sections, face flags, scenery, and sky. Use PowerShell; chain with `;` never `&&`.
5. Run steps **serially**. Do not parallelize two Godot `--headless` jobs on `godot/src`. Python converts may be sequential too (shared scratch).
6. After convert, check exit code **and** log: in-range indices, `closed: true`, scenery parse at EOF, max texture index == CMP count − 1. Orchestrator stdout must include `ShipSpawn index=` matching the catalog table.
7. If `--skip-blender` was not used, confirm three `.glb` exist and are non-tiny before treating copy as done.
8. Copy is in-place via the orchestrator (create dir on first import). Do not rename files.
9. Run Godot `--import` (`--godot-import` or a separate invocation), then `read_file` the `*.glb.import` UID lines (do not guess UIDs; `grep` can miss fresh `.import` files). `--write-scene` scenes have **no** UIDs until this step.
10. Do not hand-round `ShipSpawn`. Use orchestrator stdout or `compute_ship_spawn.py --track TRACKNN` (≥12 invariant decimals; `|v|<1e-12` → `0`). First reproduce Track01 spawn from Track01's curve JSON (`index=12`).
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
