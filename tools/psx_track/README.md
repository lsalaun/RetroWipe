# PSX → Godot asset workflows

Scripts in this folder convert `wipeout/` (extracted PSX disc) into files the
Godot port can import. Run them with `py` from anywhere; they locate the repo
root from their own path.

On this machine: Python = `py`, Blender = `blender`, Godot headless =
`d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe`. Always keep `--flip-z` and
`--units-per-meter` identical across converters for one track.

## What `wipeout/` contains vs what Godot already has

| Source | Godot today | Script |
| --- | --- | --- |
| `TRACK01`–`TRACK14` mesh/curve/flags/scene/sky | imported | `import_track.py` (re-run / TRACK15) |
| `TRACK15` | scratch glTF only, no scene | `import_track.py TRACK15 --write-scene` |
| `COMMON/ALLSH` ships | 8 GLB under `assets/ships/` | `import_ships.py` |
| `COMMON` weapons / droid / menu / FX | missing | `convert_common.py` |
| `TEXTURES/*.TIM` `*.CMP` | missing | `convert_textures.py` |
| `SOUND/WIPEOUT.VB` | missing (ship SFX slots empty) | `convert_sfx.py` / `import_audio.py` |
| `music/*.mp3` | missing | `import_audio.py` |
| `intro.mpeg` | unused in Godot | not converted |

`TRACK.INF` `outName` is a tooling leftover (TRACK15 still says `trak1`). In-game
names come from `src/wipeout/game.c` `def.circuits` (`circuit_catalog.py`).

## Commands

```powershell
# One circuit (geometry + scenery + sky + GLB + copy + spawn literal)
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py TRACK01
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py 15 --write-scene

# Ships
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py --collision

# HUD / portraits / title TIM+CMP
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES `
  D:\code\wipeout-rewrite\godot\src\assets\ui

# Weapons, rescue droid, menu models, effect sheets
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_common.py `
  D:\code\wipeout-rewrite\wipeout\COMMON `
  D:\code\wipeout-rewrite\_converted_tracks\common --flip-z

# Music MP3 + SFX WAV
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py

# Spawn transform only (row-major Transform3D, >=12 decimals)
py D:\code\wipeout-rewrite\godot\tools\psx_track\compute_ship_spawn.py `
  D:\code\wipeout-rewrite\godot\src\assets\tracks\Track_01\track_01_curve.json `
  --track TRACK01
```

After copying new GLB/PNG/WAV into `godot/src/assets/`, run a headless import
before wiring `uid://` in `.tscn` files:

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

Operational detail for circuit scenes: `godot/docs/.transactional/26-08-27-01/documentation/workflow_import_circuit.md`.
