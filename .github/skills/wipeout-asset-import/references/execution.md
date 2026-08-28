# Execution contract

This skill **runs** the import. Pasting a command list is a failure unless a step cannot run (missing dump files, missing `py`/`blender`/Godot).

## Do

1. Classify the ask: ships / textures / audio / common. If several, run **serially** in that order (ships only when regenerating existing GLBs).
2. `Test-Path` / `list_dir` the PSX sources before converting (`wipeout/COMMON/ALLSH.PRM`, `wipeout/TEXTURES`, `wipeout/SOUND/WIPEOUT.VB`, `wipeout/music/track01.mp3`, …).
3. Use `py` with absolute script paths under `godot/tools/psx_track/`. PowerShell: chain with `;`, never `&&`.
4. 3D: `--flip-z` + default `106.5` units. `import_ships.py` flips by default; `convert_common.py` needs an explicit `--flip-z`.
5. Do not parallelize two Godot `--headless` jobs on `godot/src`.
6. After each script: exit code 0 **and** log checks in the branch reference.
7. Copy in place (same filename). COMMON has **no** auto-copy — leave under `_converted_tracks/common/` unless the user named a Godot dest and asked to cable meshes.
8. After any write under `godot/src/assets/`, run:

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

If the harness uses `$ErrorActionPreference = 'Stop'`, set `Continue` around native Godot and still honor `$LASTEXITCODE`.

9. Do not kill headless Godot; let `--import` finish. `read_file` / `list_dir` fresh `.import` files (`grep` can miss them).

## Binaries

```powershell
$godot = "d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe"
# python: py
# blender: blender
```

`--path` is always `D:\code\wipeout-rewrite\godot\src`.

## Stop and report (do not improvise)

- `IndexError` / index `65280` → endian mix (TTF vs CMP, or TIM LE vs PRM BE).
- Ship/weapon mesh mirrored with `--flip-z` already on → stop; do not invent another axis.
- Empty glTF from a “curve” → wrong skill / wrong exporter.
- `convert_textures.py` on `LIBRARY.CMP` → wrong assembler; use track import.
- `Decoded N VAG` with N ≠ 30 → do not rename/pad; report.
- `--mix-rate` on SFX → wrong pitch in Godot; rerun without it.
- Temptation to rename `Dekka` → `dekka` → do not.

## PowerShell

- `py` not `python` (Store alias).
- Invariant decimal point if printing transforms (rare in this skill).
