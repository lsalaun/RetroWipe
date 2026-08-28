# Workflows d'assets PSX → Godot (hors circuit)

Documentation opérationnelle des convertisseurs ajoutés dans `godot/tools/psx_track/` pour tout ce qui n'est **pas** déjà couvert par [workflow_import_circuit.md](workflow_import_circuit.md) (pistes `TRACK01`–`TRACK14`).

Elle décrit :

- le contenu de `wipeout/` (dump disque PSX) vs ce que le port Godot consomme déjà ;
- les orchestrateurs (`import_*.py`) et convertisseurs unitaires ;
- les conventions d'axes / endianness / échelle à ne pas casser.

Les chemins ci-dessous sont relatifs à la racine du dépôt `wipeout-rewrite`, sauf mention contraire. Les commandes sont données pour Windows (PowerShell). Sur cette machine : interpréteur Python = `py` (pas `python`), Blender = `blender` (5.1), Godot headless = `d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe` si `godot4` n'est pas dans le `PATH`.

Les scripts se lancent depuis n'importe quel répertoire : ils déduisent la racine du dépôt de leur propre chemin.

---

## 1. Cartographie `wipeout/`

| Dossier / fichier | Consommé par le C | Godot (août 2026) | Workflow |
| --- | --- | --- | --- |
| `wipeout/TRACK01` … `TRACK14` | `track.c` / `scene.c` | Mesh + scène + sky + JSON déjà dans `godot/src/assets/tracks/` et `scenes/TrackNN.tscn` | [workflow_import_circuit.md](workflow_import_circuit.md) + orchestrateur `import_track.py` |
| `wipeout/TRACK15` | **absent** de `def.circuits` (`TRACK.INF` `outName = trak1`, artefact tooling) | Scratch glTF seulement, pas de scène | `import_track.py TRACK15 --write-scene` |
| `wipeout/COMMON/ALLSH.PRM` + `.CMP` | `ship.c` modèles visuels | 8 GLB sous `godot/src/assets/ships/` | [workflow_import_ships.md](workflow_import_ships.md) |
| `wipeout/COMMON/ALCOL.PRM` + `.CMP` | `ship.c` hulls collision | Non câblé (Godot utilise encore des `BoxShape3D`) | `import_ships.py --collision` |
| `wipeout/COMMON` armes / droid / menus / FX | `weapon.c`, `droid.c`, `main_menu.c`, `hud.c`, `particle.c` | Non importé | [workflow_import_common.md](workflow_import_common.md) |
| `wipeout/TEXTURES/*.TIM` `*.CMP` | HUD, portraits, title, ombres vaisseau | Non importé | [workflow_import_textures.md](workflow_import_textures.md) |
| `wipeout/SOUND/WIPEOUT.VB` | `sfx.c` (VAG ADPCM) | Slots `AudioStream` vides sur `WipeoutShip.tscn` | [workflow_import_audio.md](workflow_import_audio.md) |
| `wipeout/music/trackNN.mp3` (+ `.qoa`) | `sfx_music_play()` lit le `.qoa` | Non importé | [workflow_import_audio.md](workflow_import_audio.md) |
| `wipeout/intro.mpeg` | `intro.c` | Non utilisé par le port Godot | Pas de convertisseur |

`WIPEOUT.VH` n'est pas lu par `sfx_load()` (le VB se découpe tout seul via les flags VAG).

---

## 2. Outils (nouveaux)

Tous vivent dans `godot/tools/psx_track/`, pas dans `godot/src/tools/`.

| Script | Rôle |
| --- | --- |
| `import_track.py` | Orchestrateur pipeline A : géométrie + sections + flags + décor + ciel + GLB + copie + littéral `ShipSpawn` |
| `circuit_catalog.py` | Table `TRACKNN` → nom in-game / classe / `start_line_pos` (extrait de `src/wipeout/game.c`) |
| `compute_ship_spawn.py` | `Transform3D` yaw-only (row-major, ≥12 décimales) à l'index `start_line_pos - 15` |
| `import_ships.py` | `ALLSH` (+ option `ALCOL`) → glTF → GLB → `godot/src/assets/ships/<name>/` |
| `convert_ships.py` | Convertisseur unitaire PRM/CMP vaisseau (déjà existant, appelé par `import_ships.py`) |
| `convert_textures.py` | TIM ou CMP plat → PNG |
| `convert_sfx.py` | `WIPEOUT.VB` → un WAV par `sfx_source_t` |
| `import_audio.py` | Copie MP3 (noms `game.c`) + décode SFX vers `godot/src/assets/` |
| `convert_common.py` | Armes, rescue droid, modèles menu, feuilles FX |

Aide-mémoire court côté outils : `godot/tools/psx_track/README.md`.

---

## 3. Conventions partagées

Identiques à [workflow_import_circuit.md](workflow_import_circuit.md) §3. **Les passer à l'identique** sur tous les convertisseurs d'un même asset 3D.

- **Endianness** : PRM / TRV / TRF / TRS / TTF = **big-endian**. CMP / TIM = **little-endian**. Un `IndexError` sur un index de sous-tuile (ex. 65280) = mélange LE/BE.
- **Axes** : le C a +Y vers le bas. Les scripts nient Y. **`--flip-z` par défaut** sur les orchestrateurs (`import_track.py`, `import_ships.py`) : `(x,-y,-z)`. `--no-flip-z` n'est là que pour un diagnostic, pas pour un import « de test ».
- **Échelle** : `DEFAULT_UNITS_PER_METER = 106.5` (`psx_track_common.py`).
- **Winding PRM** : tris `(c2,c1,c0)` ; quads deux tris `(c2,c1,c0)` puis `(c2,c3,c1)`, baké avant la correction d'axes.
- **Espace local vs world** : décor/ciel bakent `origin` dans les sommets (mesh statique). Vaisseaux / armes / droid / menus **n'y touchent pas** (`object_draw()` avec le transform live).
- **CMP plat vs LIBRARY** : `TEXTURES/*.CMP`, `ALLSH.CMP`, `SCENE.CMP`, `MINE.CMP` = une TIM par entrée. `LIBRARY.CMP` + `LIBRARY.TTF` = tuiles 128×128 assemblées 4×4 — uniquement le mesh de piste.

Après toute copie dans `godot/src/assets/`, forcer un réimport headless **avant** d'écrire des `uid://` dans un `.tscn` :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

---

## 4. Ordre de travail recommandé

1. Circuits : déjà faits pour 01–14. Pour régénérer ou pour TRACK15 → [workflow_import_circuit.md](workflow_import_circuit.md) / `import_track.py`.
2. Vaisseaux : déjà faits. Régénération → [workflow_import_ships.md](workflow_import_ships.md).
3. Audio (SFX d'impact + musique menu) → [workflow_import_audio.md](workflow_import_audio.md).
4. UI / portraits → [workflow_import_textures.md](workflow_import_textures.md).
5. Armes / droid / FX quand le gameplay les instancie → [workflow_import_common.md](workflow_import_common.md).

Scratch : `_converted_tracks/` (convention existante). Livrables Godot : `godot/src/assets/`.
