# Orchestrateur d'import de circuit (`import_track.py`)

Complément de [workflow_import_circuit.md](workflow_import_circuit.md) : au lieu d'enchaîner à la main les cinq convertisseurs + Blender + copie, `godot/tools/psx_track/import_track.py` joue le **pipeline A** pour un `TRACKNN`.

Les TRACK01–TRACK14 sont déjà dans Godot. Cas d'usage : régénération, TRACK15, ou une piste dont les GLB ont divergé du dump PSX.

Python = `py`, Blender = `blender`. `--flip-z` et le même `--units-per-meter` sont poussés sur **tous** les convertisseurs.

---

## 1. Ce que fait une run

Pour `TRACKNN` / `NN` :

1. Vérifie `wipeout/TRACKNN/` (`TRACK.TRV/TRF/TRS`, `LIBRARY.CMP/TTF`, `SCENE.PRM/CMP`, `SKY.PRM/CMP`).
2. Affiche le nom `circuit_catalog.py` (`def.circuits`). TRACK15 : `in_game=False`.
3. Écrit dans `_converted_tracks/track_NN/` :
   - `Track_NN_mesh.gltf` (+ textures)
   - `track_NN_curve.json`
   - `track_NN_face_flags.json`
   - `Track_NN_scene.gltf`
   - `Track_NN_sky.gltf`
4. Ré-exporte les 3 glTF → `.glb` via `godot/tools/blender/convert_track_mesh.py`.
5. Copie GLB + JSON vers `godot/src/assets/tracks/Track_NN/` (même nom → UID conservés).
6. Imprime le `Transform3D` yaw-only à l'index `start_line_pos - 15` (pas le point 0).

Le détail mesh / courbe / flags / décor / `ShipSpawn` / piège row-major reste dans [workflow_import_circuit.md](workflow_import_circuit.md) §§3–6.

---

## 2. Commandes

Régénérer Terramax (TRACK01) sans toucher au `.tscn` :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py TRACK01
```

TRACK15 + ébauche de scène (si `Track15.tscn` n'existe pas) :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py TRACK15 --write-scene
```

`--overwrite-scene` est **requis** pour écraser un `TrackNN.tscn` existant (01–14). Ne pas le faire à la légère : les UID `ext_resource` déjà validés partent.

Conversion sans Blender / sans copie (debug parse) :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py 12 --skip-blender --skip-copy
```

Réimport Godot en fin de run :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_track.py TRACK15 --godot-import
```

Binaire par défaut : `d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe`. Surcharge : `--godot-bin`.

Spawn seul (JSON déjà produit) :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\compute_ship_spawn.py `
  D:\code\wipeout-rewrite\godot\src\assets\tracks\Track_01\track_01_curve.json `
  --track TRACK01
```

Contrôle : le littéral TRACK01 doit matcher `scenes/Track01.tscn` (`index=12`, origin `(-356.807511737089, 3.164319248826, 299.417840375587)`, `basis.y = (0,1,0)`).

---

## 3. Catalogue `start_line_pos`

`circuit_catalog.py` / `game.c` `def.circuits[].settings[].start_line_pos`. Index Godot = valeur − 15.

| TRACK | Circuit (affichage) | Classe | `start_line_pos` | Index spawn |
| --- | --- | --- | --- | --- |
| 01 | TERRAMAX | venom | 27 | 12 |
| 02 | ALTIMA VII | venom | 27 | 12 |
| 03 | ALTIMA VII RAPIER | rapier | 27 | 12 |
| 04 | KARBONIS V | venom | 16 | 1 |
| 05 | KARBONIS V RAPIER | rapier | 16 | 1 |
| 06 | TERRAMAX RAPIER | rapier | 27 | 12 |
| 07 | KORODERA RAPIER | rapier | 16 | 1 |
| 08 | ARRIDOS IV | venom | 16 | 1 |
| 09 | SILVERSTREAM | venom | 16 | 1 |
| 10 | FIRESTAR | venom | 27 | 12 |
| 11 | ARRIDOS IV RAPIER | rapier | 16 | 1 |
| 12 | KORODERA | venom | 16 | 1 |
| 13 | SILVERSTREAM RAPIER | rapier | 16 | 1 |
| 14 | FIRESTAR RAPIER | rapier | 27 | 12 |
| 15 | *(test, pas in-game)* | — | 27 (défaut) | 12 |

`TRACK.INF` `outName` **n'est pas** une source de vérité (TRACK15 dit `trak1`).

---

## 4. Flags CLI

| Flag | Effet |
| --- | --- |
| `--no-flip-z` | Omet `--flip-z` partout (miroir). Ne pas utiliser pour un livrable. |
| `--units-per-meter` | Défaut `106.5` |
| `--skip-blender` | Pas de GLB |
| `--skip-copy` | Ne touche pas `godot/src/assets/tracks/` |
| `--write-scene` | Écrit `godot/src/scenes/TrackNN.tscn` s'il est absent |
| `--overwrite-scene` | Autorise l'écrasement du `.tscn` |
| `--godot-import` | `godot --headless --path godot/src --import` |
| `--scratch` / `--wipeout-root` / `--godot-assets` | Chemins non standards |

La scène générée n'a **pas** d'UID `ext_resource` : les remplir après `--godot-import` en lisant les `*.glb.import`, ou laisser Godot les réécrire à l'ouverture éditeur.

---

## 5. Suite

Validation headless, collider trimesh, piège `Transform3D` : [workflow_import_circuit.md](workflow_import_circuit.md) §§6–8.

Vue d'ensemble des autres dumps (`TEXTURES`, `SOUND`, `COMMON`) : [workflow_assets_overview.md](workflow_assets_overview.md).
