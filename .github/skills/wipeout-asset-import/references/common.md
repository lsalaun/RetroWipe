# COMMON — weapons, droid, menu, FX

Long form: `docs/.transactional/26-08-27-01/documentation/workflow_import_common.md`.

Same PRM+flat CMP as ships. **Local space** (`origin` not baked). Must pass `--flip-z`. No auto-copy into `godot/src/assets/` — Godot does not instance these yet.

ALLSH/ALCOL → [ships.md](./ships.md), not this file.

## Groups (`convert_common.py`)

### weapons (`weapon.c`) — all share `MINE.CMP`

| PRM | glTF prefix |
| --- | --- |
| `ROCK.PRM` | `rocket` |
| `MINE.PRM` | `mine` |
| `MISS.PRM` | `missile` |
| `SHLD.PRM` | `shield` (C also uses as `shield_internal`; one export) |
| `EBOLT.PRM` | `ebolt` |

Sanity (already run): missile 17/30, mine1 14/24, cube1 21/38, shield 58/112, sphere1 26/48 (verts/tris).

### droid (`droid.c`)

`RESCU.PRM` + `RESCU.CMP` → `rescue_droid`. Also used on the menu — one asset, two references, do not duplicate.

### menu (`main_menu.c`)

`LEEG`, `TEAMS` (no CMP), `PILOT`, `ALOPT`, `PAD1`, `MSDOS` + matching CMP where present.

### fx (textures only)

`EFFECTS.CMP` (`particle.c`), `WICONS.CMP` (`hud.c` weapon icons) via `convert_textures.py` path inside `convert_common.py`.

Do not convert leftover COMMON PRM (`CAM*S`, `HEAD`, `NEG`, `SFX`, `SHP*S`, …) without a C consumer.

## Run

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_common.py `
  D:\code\wipeout-rewrite\wipeout\COMMON `
  D:\code\wipeout-rewrite\_converted_tracks\common `
  --flip-z
```

One group: `--only weapons|droid|menu|fx` (default `all`).

Optional GLB (same Blender script as tracks), then **manual** copy if the user asked to cable a mesh:

```powershell
blender --background --python D:\code\wipeout-rewrite\godot\tools\blender\convert_track_mesh.py -- `
  D:\code\wipeout-rewrite\_converted_tracks\common\weapons\rocket.gltf `
  D:\code\wipeout-rewrite\_converted_tracks\common\weapons\rocket.glb
```

Then `--import` only if copied under `godot/src/assets/`.

## Checks

- PRM loop lands at EOF.
- Max texture index == `len(CMP) - 1` when a CMP exists.
- `TEAMS.PRM` untextured / `COLOR_0` only.
- TSPR/BSPR/splines/lights: parsed, not meshed.
