# Workflow d'import COMMON (armes, droid, menus, FX)

Documentation opérationnelle pour les PRM/CMP de `wipeout/COMMON` **autres** que les vaisseaux (`ALLSH` / `ALCOL` : [workflow_import_ships.md](workflow_import_ships.md)).

Python = `py`. Format identique à `convert_track_scenery.py` / `convert_ships.py` (`parse_prm` + CMP plat). Les modèles sont exportés en **espace local** (`origin` non baké), comme les vaisseaux.

---

## 1. Sources PSX (ce que le C charge vraiment)

Groupes de `convert_common.py`, alignés sur les `objects_load()` / `image_get_compressed_textures()` du C :

### 1.1 `weapons` — `src/wipeout/weapon.c`

Toutes les géométries partagent `MINE.CMP` :

| PRM | Préfixe glTF | Usage |
| --- | --- | --- |
| `ROCK.PRM` | `rocket` | Roquettes |
| `MINE.PRM` | `mine` | Mines |
| `MISS.PRM` | `missile` | Missile |
| `SHLD.PRM` | `shield` | Bouclier (aussi `shield_internal`) |
| `EBOLT.PRM` | `ebolt` | Electro-bolt |

Contrôle déjà exécuté : `missile` 17 verts / 30 tris, `mine1` 14/24, `cube1` 21/38, `shield` 58/112, `sphere1` 26/48.

### 1.2 `droid` — `src/wipeout/droid.c`

| PRM | CMP | Préfixe |
| --- | --- | --- |
| `RESCU.PRM` | `RESCU.CMP` | `rescue_droid` |

### 1.3 `menu` — `src/wipeout/main_menu.c`

| PRM | CMP | Préfixe |
| --- | --- | --- |
| `LEEG.PRM` | `LEEG.CMP` | `race_classes` |
| `TEAMS.PRM` | *(aucune)* | `teams` (couleurs sommets) |
| `PILOT.PRM` | `PILOT.CMP` | `pilots` |
| `ALOPT.PRM` | `ALOPT.CMP` | `options` |
| `PAD1.PRM` | `PAD1.CMP` | `controller` |
| `MSDOS.PRM` | `MSDOS.CMP` | `misc` |

### 1.4 `fx` — textures seules

| CMP | Consommateur C |
| --- | --- |
| `EFFECTS.CMP` | `particle.c` |
| `WICONS.CMP` | `hud.c` icônes d'armes |

Pas de PRM : `convert_textures.py` écrit des PNG.

Le dossier `COMMON` contient d'autres PRM (`CAM*S`, `HEAD`, `NEG`, `SFX`, `SHP*S`, …) **non listés** ici : le C ne les charge pas dans les chemins portés. Ne pas les convertir « au cas où » sans un consommateur.

---

## 2. Outil

`godot/tools/psx_track/convert_common.py`

- `--only weapons|droid|menu|fx|all` (défaut `all`)
- `--flip-z` : **le passer** pour rester aligné sur pistes / vaisseaux
- `--units-per-meter` défaut `106.5`

Sortie : `_converted_tracks/common/<groupe>/*.gltf` (+ `*_textures/`). Pas de copie automatique vers `godot/src/assets/` (aucun nœud Godot ne les instance encore). Ré-export GLB avec le même script Blender que les pistes, **si** on câble un mesh.

---

## 3. Commandes

Tout COMMON (sauf ALLSH) vers le scratch :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_common.py `
  D:\code\wipeout-rewrite\wipeout\COMMON `
  D:\code\wipeout-rewrite\_converted_tracks\common `
  --flip-z
```

Un groupe :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_common.py `
  D:\code\wipeout-rewrite\wipeout\COMMON `
  D:\code\wipeout-rewrite\_converted_tracks\common `
  --only weapons --flip-z
```

GLB (exemple, une arme) :

```powershell
blender --background --python D:\code\wipeout-rewrite\godot\tools\blender\convert_track_mesh.py -- `
  D:\code\wipeout-rewrite\_converted_tracks\common\weapons\rocket.gltf `
  D:\code\wipeout-rewrite\_converted_tracks\common\weapons\rocket.glb
```

Puis copier à la main vers p.ex. `godot/src/assets/weapons/` et `godot --headless --path godot/src --import`.

---

## 4. Contrôles

- Parse PRM : la boucle atterrit en EOF (même règle que le décor).
- Max des indices texture = `len(CMP) - 1` quand un CMP est fourni.
- `TEAMS.PRM` sans CMP : groupes untexturés / `COLOR_0` uniquement.
- Sprites `TSPR`/`BSPR`, splines, lumières : parsés, **pas** meshés.

---

## 5. Limites

- Godot n'instancie pas encore ces GLB (pas de pickup d'armes, pas de droid, menus 2D).
- `SHLD.PRM` est chargé deux fois côté C (externe + interne) ; un seul export suffit.
- `RESCU` sert aussi au modèle menu (`main_menu.c`) : ne pas dupliquer l'asset, le référencer deux fois.
