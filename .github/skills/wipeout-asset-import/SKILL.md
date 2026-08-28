---
name: wipeout-asset-import
description: "Import Wipeout PSX non-track assets into the Godot port: ships (ALLSH/ALCOL), TIM/CMP 2D textures, SFX (WIPEOUT.VB) and music MP3, COMMON weapons/droid/menu/FX. Use when: import_ships.py, convert_ships.py, convert_textures.py, import_audio.py, convert_sfx.py, convert_common.py, ALLSH, ALCOL, portraits, HUD TIM, VAG, WIPEOUT.VB, MINE.PRM, ROCK.PRM, RESCU, EFFECTS.CMP, WICONS.CMP."
argument-hint: ships | textures | audio | common
---

# Wipeout asset import (ships, TIM, audio, COMMON)

Specialist workflow for PSX dumps that are **not** circuits. **Execute** the converters (Python, Blender when needed, Godot `--import`). Do not dump command lists unless blocked (missing `wipeout/` files, missing `py`/`blender`/Godot). Do not improvise axis flips, endianness, PRM names, or WAV sample rates.

Circuits (`TRACKNN`, `import_track.py`) belong to **wipeout-track-import**, not this skill.

Canonical docs:

- `docs/.transactional/26-08-27-01/documentation/workflow_assets_overview.md`
- `workflow_import_ships.md` / `workflow_import_textures.md` / `workflow_import_audio.md` / `workflow_import_common.md`

Execution: [execution.md](./references/execution.md). Shared format rules: [conventions.md](./references/conventions.md).

## When to use

| User ask | Branch |
| --- | --- |
| Ships / pilots / ALLSH / ALCOL / regenerate GLB under `assets/ships/` | [ships.md](./references/ships.md) |
| HUD, title, portraits, `TEXTURES/*.tim` `*.cmp`, speedo, shad1–4 | [textures.md](./references/textures.md) |
| SFX, VAG, `WIPEOUT.VB`, music MP3 / QOA | [audio.md](./references/audio.md) |
| Weapons, rescue droid, menu PRM, EFFECTS/WICONS | [common.md](./references/common.md) |

Do **not** use for `LIBRARY.CMP`+`TTF` (track tiles), `SCENE.PRM`/`SKY.PRM`, `TrackNN.tscn`, or `ShipSpawn`.

Eight ship GLBs already exist. TIM/SFX/COMMON are largely **not** wired in Godot yet: convert + copy + `--import`; do not invent menu/HUD scenes unless the user asked to cable them.

## Machine / paths

Relative to wipeout-rewrite repo root (`d:\code\wipeout-rewrite`).

| Role | This machine |
| --- | --- |
| Python | `py` (not `python`) |
| Blender | `blender` (5.1) — ships + COMMON meshes only |
| Godot | `d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe` `--path godot/src` |
| Scratch | `_converted_tracks/` (`ships/`, `common/`, `sfx_probe/`, `ui_probe/`) |
| Deliverables | `godot/src/assets/ships/`, `ui/`, `sfx/`, `music/`, `weapons/` (if cabled) |

Scripts live in `godot/tools/psx_track/`, **not** `godot/src/tools/`. They resolve repo root from `__file__`; any cwd is fine.

## Decision tree

```text
Non-track wipeout/ dump → Godot?
├─ ALLSH / pilot mesh / ALCOL     → import_ships.py     (ships.md)
├─ TEXTURES TIM/CMP / portraits   → convert_textures.py (textures.md)
├─ SOUND/WIPEOUT.VB or music/*.mp3 → import_audio.py    (audio.md)
└─ COMMON weapons/droid/menu/FX   → convert_common.py   (common.md)
```

If the user says “import everything left”, run **serially**: ships (only if regenerating) → audio → textures → common. Never two Godot `--headless` jobs on `godot/src` at once.

## Hard rules

1. `--flip-z` on 3D PRM exports (ships, weapons, droid, menu). `import_ships.py` enables it by default. `convert_common.py` does **not** — you must pass `--flip-z`. `--no-flip-z` is diagnostic only.
2. Same `--units-per-meter` (default `106.5`) on every 3D convert of a given asset family.
3. Ships / weapons / droid / menu: **local space** (`origin` not baked). Scenery/sky (other skill) bake origin. Do not “fix” ship GLBs by baking world origin.
4. Flat CMP (`TEXTURES/*.cmp`, `ALLSH.CMP`, `MINE.CMP`) ≠ `LIBRARY.CMP`+TTF. Never point `convert_textures.py` at `LIBRARY.CMP`.
5. Keep PRM object names (`Dekka` capital D). Do not rename folders to match `def.pilots` order.
6. Overwrite GLB/PNG/WAV **in place** (same filename) so `.import` UIDs survive. After copy: Godot `--import` before writing `uid://` in `.tscn`.
7. Audio: content rate, not mix rate. Non-voice WAV = 22050 Hz; voices = 44100. Do not pass `convert_sfx.py --mix-rate` for Godot.
8. `ALCOL` hulls stay in scratch unless the user asked to replace `BoxShape3D`. COMMON GLB are not auto-copied into `godot/src/assets/`.
9. Execute; check exit code **and** logs. Stop on `IndexError` / endian garbage — do not patch indices.

## Default commands

Ships (regenerate 8 visuals, copy in place):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py
```

Textures → `godot/src/assets/ui`:

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES `
  D:\code\wipeout-rewrite\godot\src\assets\ui
```

Audio (11 MP3 + 30 WAV):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py
```

COMMON scratch (pass `--flip-z`):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_common.py `
  D:\code\wipeout-rewrite\wipeout\COMMON `
  D:\code\wipeout-rewrite\_converted_tracks\common `
  --flip-z
```

Then Godot import:

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

## Done when

- [ ] Correct branch script ran; `--flip-z` on every 3D PRM step
- [ ] Deliverables in the paths above (or scratch if `--skip-copy` / COMMON)
- [ ] Ship names match PRM (`Dekka/`); 8 GLBs if ships
- [ ] TIM/CMP: expected WxH (e.g. `speedo.tim` 128×32); CMP frames written
- [ ] Audio: `Decoded 30 VAG region(s)`; voices 44100; others 22050; MP3 renamed per `game.c`
- [ ] COMMON: PRM parse hits EOF; max texture index == CMP count − 1
- [ ] `--import` run if files landed under `godot/src/assets/`
- [ ] No invented HUD/weapon scenes unless requested
- [ ] Track pipeline untouched

## Out of scope

`intro.mpeg`; QOA re-encode; `WIPEOUT.VH`; `LIBRARY.TEX`; wiring `MainMenu.tscn` / weapon pickups; replacing ship `BoxShape3D` with ALCOL; input map; track import.
