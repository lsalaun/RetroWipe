# Portée des imports d'assets hors circuit

Décisions de cadrage pour `wipeout-asset-import` (vaisseaux, TIM/CMP, audio, COMMON). Calées sur ce que le runtime Godot **consomme déjà**, pas sur ce que le dump PSX permet.

Skill : `godot/.github/skills/wipeout-asset-import/`.
Docs : `godot/docs/.transactional/26-08-27-01/documentation/workflow_assets_overview.md` et les `workflow_import_{ships,textures,audio,common}.md`.

---

## Règle

N'écrire sous `godot/src/assets/` que ce qui a un consommateur (ou un slot vide évident). Le reste reste dans `_converted_tracks/` jusqu'au câblage.

| Livrable | Destination | Câbler maintenant ? |
| --- | --- | --- |
| ALLSH GLB | `godot/src/assets/ships/` (déjà) | non (déjà fait) |
| ALCOL | scratch | non |
| COMMON PRM | `_converted_tracks/common/` | non |
| TIM/CMP | scratch, ou `assets/ui` sans scènes | non |
| WAV/MP3 | `assets/sfx/` + `assets/music/` | seulement `crunch.wav` → Wall/Ship impact |

---

## 1. COMMON : rester en `_converted_tracks/common/`

`godot/src/assets/` n'est pas un dépôt de dump : c'est ce que le runtime charge. Les pistes et les 8 vaisseaux y sont parce que `TrackNN.tscn` / `ship_selection.gd` les référencent. Rien n'instancie rocket / mine / droid / menu.

Copier maintenant :

- pollue le projet (glTF + PNG + éventuellement GLB orphelins) ;
- force des `.import` / UID pour des meshes sans nœud ;
- fige des noms de dossiers (`weapons/rocket.glb` ?) avant d'avoir le graphe d'armes.

Le jour où un pickup ou le droid existe, **alors** Blender → GLB → copie **du seul mesh** concerné, comme pour une piste. `SHLD` une fois, `RESCU` une fois (menu + in-game = deux références, un asset).

Exception mince : `WICONS.CMP` / `EFFECTS.CMP` si le HUD est câblé tout de suite — et encore, via le flux textures, pas tout COMMON.

---

## 2. PNG/WAV : conversion + un branchement SFX, pas le HUD

**UI / portraits :** conversion seule. `MainMenu` / `PilotMenu` sont du texte. Coller `speedo.png` ou `dekka_00.png` dans `assets/ui` sans `TextureRect` / atlas, c'est le même piège que COMMON dans `assets/`. Convertir (scratch, ou `assets/ui` **si** le layout de dossiers est décidé) ; ne pas inventer le HUD dans le skill d'import.

**Audio :** coller `crunch.wav` sur les slots déjà là, rien de plus.

`WallImpactSFX` / `ShipImpactSFX` existent déjà (`WipeoutShip.tscn`, `WipeoutShipAI.tscn`), exports `AudioStream` vides. Le C joue `SFX_CRUNCH` dans les deux cas. C'est un assignement de ressource, pas un système audio. Ça valide le décodeur VAG en jeu (mur + vaisseau) sans bus, musique, ni voix.

**Musique :** copier les MP3 dans `assets/music/` est raisonnable (fichiers stables, noms `game.c`). Les faire jouer implique un `AudioStreamPlayer` + boucle menu/course — autre tâche.

---

## 3. Un skill unique, pas un skill par dump

Garder `wipeout-asset-import`.

Les quatre dumps partagent endianness, `--flip-z`, `106.5`, CMP plat vs `LIBRARY`, `py` / `blender` / Godot `--import`, et l'interdiction d'improviser des scènes. Quatre skills, c'est quatre fois les mêmes hard rules et un agent qui se trompe de skill (`dekka.cmp` vs `Dekka.glb`).

Le découpage utile est **déjà** dans les références (`ships` / `textures` / `audio` / `common`) + `argument-hint`. Un skill par dump n'apporte que de la découverte `/` plus bruyante.

Séparer plus tard seulement si un flux devient un **gros** chantier runtime (vrai HUD, vrais pickups) — ce ne sera plus un skill d'import, ce sera un skill gameplay.

Les circuits restent dans `wipeout-track-import` (`import_track.py`), hors de ce skill.
