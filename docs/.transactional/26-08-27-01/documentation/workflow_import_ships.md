# Workflow d'import des vaisseaux (COMMON/ALLSH → Godot)

Documentation opérationnelle du pipeline d'import des modèles pilotes. Les 8 GLB sont déjà dans `godot/src/assets/ships/` ; ce document sert à **régénérer** ou à extraire les hulls `ALCOL`.

Les chemins sont relatifs à la racine `wipeout-rewrite`. Python = `py`, Blender = `blender`.

---

## 1. Sources PSX

| Fichier | Usage C | Export Godot |
| --- | --- | --- |
| `wipeout/COMMON/ALLSH.PRM` + `ALLSH.CMP` | `ships_load()` / `object_draw()` avec le transform live du vaisseau | Un mesh texturé par objet PRM |
| `wipeout/COMMON/ALCOL.PRM` + `ALCOL.CMP` | `ship_intersects_ship()` (proxy collision bas poly) | GLB optionnels, **non câblés** (Godot utilise encore des `BoxShape3D`) |

`ALLSH.PRM` contient 8 objets, nommés d'après le pilote (ordre PRM, pas l'ordre `def.pilots`) :

| Objet PRM | Dossier Godot | Affichage (`ship_selection.gd`) |
| --- | --- | --- |
| `sophia` | `godot/src/assets/ships/sophia/sophia.glb` | Sofia De La Rente / Feisar |
| `solaar` | `…/solaar/solaar.glb` | Kel Solaar / Qirex |
| `jacko` | `…/jacko/jacko.glb` | Paul Jackson / Feisar |
| `chang` | `…/chang/chang.glb` | Daniel Chang / AG Systems |
| `arian` | `…/arian/arian.glb` | Arian Tetsuo / Qirex |
| `arial` | `…/arial/arial.glb` | Arial Tetsuo / Auricom |
| `anasta` | `…/anasta/anasta.glb` | Anastasia Cherovoski / Auricom |
| `Dekka` | `…/Dekka/Dekka.glb` | John Dekka / AG Systems |

Le `D` majuscule de `Dekka` vient du nom d'objet PRM ; ne pas le « corriger » ou le `.tscn` / `ship_selection.gd` cassent.

Portraits 2D (`wipeout/TEXTURES/dekka.cmp`, `chang.cmp`, …) : [workflow_import_textures.md](workflow_import_textures.md), pas ce pipeline.

---

## 2. Outils

| Script | Rôle |
| --- | --- |
| `godot/tools/psx_track/import_ships.py` | Orchestrateur : `convert_ships.py` → Blender GLB → copie |
| `godot/tools/psx_track/convert_ships.py` | PRM+CMP → un `.gltf` (+ PNG) par objet, **espace local** (`origin` non baké) |
| `godot/tools/blender/convert_track_mesh.py` | glTF + PNG externes → `.glb` autonome (même script que les pistes) |

Contrairement au décor de piste, `ships_load()` n'applique jamais `origin`. Les sommets restent dans l'espace modèle, prêts à être parentés sous `ShipVisual`.

`--flip-z` est **activé par défaut** dans `import_ships.py` (même convention que le pipeline A des circuits). `--units-per-meter` défaut = `106.5`.

---

## 3. Commandes

Régénérer les 8 visuels et les copier (écrase les GLB en place, UID / `.import` conservés si le nom de fichier ne change pas) :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py
```

Scratch : `_converted_tracks/ships/<name>.gltf` puis `.glb`. Destination : `godot/src/assets/ships/<name>/<name>.glb`.

Hulls collision uniquement (restent dans `_converted_tracks/ship_collision/`, **pas** copiés dans Godot) :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_ships.py --collision --skip-copy
```

Convertisseur unitaire (sans Blender, sans copie) :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_ships.py `
  D:\code\wipeout-rewrite\wipeout\COMMON\ALLSH.PRM `
  D:\code\wipeout-rewrite\wipeout\COMMON\ALLSH.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\ships `
  --flip-z
```

Flags utiles de `import_ships.py` :

| Flag | Effet |
| --- | --- |
| `--skip-blender` | S'arrête au glTF |
| `--skip-copy` | Ne touche pas `godot/src/assets/ships/` |
| `--no-flip-z` | Diagnostic miroir uniquement |
| `--common` | Autre dossier que `wipeout/COMMON` |

Après copie, réimport headless si des UID manquent :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

---

## 4. Câblage Godot

`godot/src/scripts/ship_selection.gd` (autoload) mappe `mesh` → chemin GLB. `main.tscn` charge `selected_ship_scene` sur le vaisseau joueur.

`WipeoutShip.tscn` : le visuel va sous `ShipVisual` ; `BodyMesh` / `Canopy` sont des placeholders (boîtes) tant qu'un GLB n'est pas instancié.

Les `AudioStream` d'impact (`WallImpactSFX`, `ShipImpactSFX`) ne viennent **pas** de ce workflow : [workflow_import_audio.md](workflow_import_audio.md) (`crunch.wav`, `impact.wav`).

---

## 5. Contrôles

- Log de `convert_ships.py` : 8 objets, indices de texture dans la plage CMP, triangles > 0.
- Un GLB miroir gauche/droite alors que `--flip-z` était passé : ne pas improviser un autre axe ; diagnostiquer (même règle que les pistes).
- Ne pas fusionner les 8 vaisseaux dans un seul GLB.

---

## 6. Limites

- `ALCOL` n'alimente pas encore les `CollisionShape3D` (boîtes plus étroites que l'AABB rendu, volontaire).
- Ombres sol (`wipeout/TEXTURES/shad1.tim` … `shad4.tim`) : textures UI/FX, pas des meshes vaisseau.
- `def.ship_model_to_pilot` dans `game.c` réordonne modèle → pilote ; Godot suit les **noms d'objets PRM**, pas cet index.
