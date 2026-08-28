# Ships — ALLSH / ALCOL

Long form: `docs/.transactional/26-08-27-01/documentation/workflow_import_ships.md`.

## Sources

| File | C | Godot |
| --- | --- | --- |
| `wipeout/COMMON/ALLSH.PRM` + `ALLSH.CMP` | `ships_load()` / live `object_draw()` | 8 textured GLB |
| `wipeout/COMMON/ALCOL.PRM` + `ALCOL.CMP` | `ship_intersects_ship()` | scratch only; Godot still `BoxShape3D` |

Portraits (`wipeout/TEXTURES/dekka.cmp`, …) → [textures.md](./textures.md).

## PRM names (locked)

Order is PRM object order, **not** `def.pilots`.

| PRM object | Path |
| --- | --- |
| `sophia` | `godot/src/assets/ships/sophia/sophia.glb` |
| `solaar` | `…/solaar/solaar.glb` |
| `jacko` | `…/jacko/jacko.glb` |
| `chang` | `…/chang/chang.glb` |
| `arian` | `…/arian/arian.glb` |
| `arial` | `…/arial/arial.glb` |
| `anasta` | `…/anasta/anasta.glb` |
| `Dekka` | `…/Dekka/Dekka.glb` |

Do not lowercase `Dekka`.

Local space: `origin` not baked. `--flip-z` default. Scale `106.5`.

## Run

Regenerate visuals and overwrite in place (UID kept if filename unchanged):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py
```

Scratch: `_converted_tracks/ships/<name>.gltf` → `.glb`. Dest: `godot/src/assets/ships/<name>/<name>.glb`.

ALCOL hulls (scratch `_converted_tracks/ship_collision/`, **not** copied):

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py --collision --skip-copy
```

| Flag | Effect |
| --- | --- |
| `--skip-blender` | Stop at glTF |
| `--skip-copy` | Do not touch `godot/src/assets/ships/` |
| `--no-flip-z` | Mirror diagnostic |
| `--collision` | Also convert ALCOL |

Unit converter:

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_ships.py `
  D:\code\wipeout-rewrite\wipeout\COMMON\ALLSH.PRM `
  D:\code\wipeout-rewrite\wipeout\COMMON\ALLSH.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\ships `
  --flip-z
```

Then `--import` if files landed in `godot/src/assets/`.

## Wiring (do not invent)

`ship_selection.gd` maps `mesh` → GLB path. Visual under `WipeoutShip` `ShipVisual`. `BodyMesh`/`Canopy` are placeholders. Impact SFX are [audio.md](./audio.md), not this branch.

## Checks

- Log: 8 objects, texture indices in CMP range, tris > 0.
- Mirror with `--flip-z` on → stop; no extra axis.
- Do not merge 8 ships into one GLB.
