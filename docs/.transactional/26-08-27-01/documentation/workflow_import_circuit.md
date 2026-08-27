# Workflow d'import d'un circuit (PSX → Godot)

Documentation opérationnelle du pipeline d'import de piste pour le port Godot. Elle décrit :

- les convertisseurs Python/Blender (`godot/tools/`) qui extraient les données PSX ;
- l'intégration dans une scène Godot (`TrackNN.tscn` + assets) ;
- les scripts headless de `godot/src/tools/` utilisés pour inspecter et valider le circuit une fois importé.

Les chemins ci-dessous sont relatifs à la racine du dépôt `wipeout-rewrite`, sauf mention contraire. Les commandes sont données pour Windows (PowerShell). Sur cette machine : interpréteur Python = `py` (pas `python`), Blender = `blender` (installé en 5.1), Godot headless = `d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe` si `godot4` n'est pas dans le `PATH`.

---

## 1. Cartographie des outils

### 1.1 Conversion (hors `src/tools`)

Les parsers et ré-exports vivent dans `godot/tools/`, pas dans `godot/src/tools/`.

| Outil | Rôle |
| --- | --- |
| `godot/tools/psx_track/convert_track_geometry.py` | `TRACK.TRV` + `TRACK.TRF` (+ `LIBRARY.CMP`/`LIBRARY.TTF`) → mesh texturé `.gltf`/`.obj` |
| `godot/tools/psx_track/convert_track_sections.py` | `TRACK.TRS` → JSON de ligne centrale IA |
| `godot/tools/psx_track/convert_track_face_flags.py` | flags de faces (`pickup` / `boost` / `start_grid`) → JSON |
| `godot/tools/psx_track/convert_track_scenery.py` | `SCENE.PRM`+`SCENE.CMP` ou `SKY.PRM`+`SKY.CMP` → mesh décor/ciel |
| `godot/tools/psx_track/psx_track_common.py` | parseurs partagés (TRV/TRF/CMP/TTF/PRM/TIM, axes, échelle) |
| `godot/tools/blender/convert_track_mesh.py` | glTF + PNG externes → `.glb` autonome (textures embarquées) |
| `godot/tools/blender/export_track_curve.py` | courbe Blender (Bezier/Poly) → JSON `Curve3D` (sans passer par glTF) |
| `godot/tools/blender/import_track_curve.py` | JSON de ligne centrale → `.blend` d'inspection |

### 1.2 Inspection / validation (`godot/src/tools`)

Ces scripts `extends SceneTree` se lancent en Godot headless (`-s`). Ils ne convertissent rien : ils vérifient qu'un circuit déjà câblé dans le projet se comporte correctement.

| Script | Rôle |
| --- | --- |
| `godot/src/tools/inspect_scene.gd` | Dump récursif d'une scène/GLB (hiérarchie, AABB, points de courbe) |
| `godot/src/tools/inspect_ai_track_alignment.gd` | Mesure l'erreur latérale vaisseau ↔ `CenterLine` dans `main.tscn` |
| `godot/src/tools/validate_track_side_walls.gd` | Vérifie que les bords de `Track01` sont des murs (trimesh), pas des rampes |
| `godot/src/tools/validate_ai_field.gd` | Vérifie le plateau de course : 1 joueur + 7 IA, mouvement, rangs uniques |
| `godot/src/tools/setup_input_map.gd` | Hors import de piste : régénère la section `[input]` de `project.godot` |

### 1.3 Consommateurs runtime (côté scène)

| Script | Rôle |
| --- | --- |
| `godot/src/scripts/track_center_line.gd` | Charge le JSON de courbe dans un `Path3D` / `Curve3D` |
| `godot/src/scripts/track_mesh_collider.gd` | Trimesh + `backface_collision` + matériaux double-face sur `TrackMesh` uniquement |
| `godot/src/scripts/track_gameplay_zones.gd` | Instancie pads de boost (`Area3D`) et marqueurs pickup / grille |
| `godot/src/scripts/track_boost_pad.gd` | Impulsion de vitesse au contact d'un pad |

---

## 2. Données source PSX

Chaque dossier `wipeout/TRACKNN/` contient les fichiers lus par le moteur original. Pour l'import Godot, seuls ceux-ci comptent :

| Fichier | Usage |
| --- | --- |
| `TRACK.TRV` | Sommets de la piste (big-endian) |
| `TRACK.TRF` | Faces (quads, texture id, flags, couleur) |
| `TRACK.TRS` | Sections : centres, `next`/`prev`, flags `jump`/jonction |
| `LIBRARY.CMP` + `LIBRARY.TTF` | Textures de piste (tuiles 128×128 assemblées en 4×4 sous-tuiles 32×32) |
| `SCENE.PRM` + `SCENE.CMP` | Décor (tribunes, portique, pompes, etc.) |
| `SKY.PRM` + `SKY.CMP` | Dôme de ciel |

`TRACK.INF` (`outName = trakNN`) est un artefact de tooling, pas lu par le moteur. Pour le nom in-game / la classe, se référer à `src/wipeout/game.c` (`def.circuits`, champ `.path = "wipeout/trackNN/"`). Exemples déjà vérifiés :

- `TRACK01` → Terramax (`CIRCUIT_TERRAMAX`, Venom)
- `TRACK02` → Altima VII (`CIRCUIT_ALTIMA_VII`, Venom)

Convention de travail : les intermédiaires vont dans `_converted_tracks/` (à la racine du dépôt). Les livrables Godot vont dans `godot/src/assets/tracks/Track_NN/`.

---

## 3. Conventions d'espace (à garder identiques sur toute une piste)

Tous les convertisseurs Python partagent les mêmes options. **Les passer à l'identique** sur géométrie, sections, flags et décor, sinon mesh / courbe / pads ne coïncident plus.

- **Endianness** : `TRACK.TRV` / `TRF` / `TRS` et `LIBRARY.TTF` / `SCENE.PRM` sont **big-endian**. `LIBRARY.CMP` / `SCENE.CMP` / `SKY.CMP` (en-tête + TIM) sont **little-endian**. Un `IndexError` sur un index de sous-tuile (ex. 65280) est le symptôme classique d'un mélange LE/BE.
- **Axes** : le moteur source a +Y vers le bas. Les scripts nient Y (Godot/glTF = +Y up). **Sans `--flip-z`** le transform est `(x,-y,z)` — une **réflexion** (gauche/droite inversés, pubs à l'envers). **Le pipeline A passe `--flip-z` par défaut** : `(x,-y,-z)` (rotation). Le flag va sur **tous** les convertisseurs (géométrie, sections, flags, décor, ciel). Ne pas l'omettre « pour tester ».
- **Échelle** : `DEFAULT_UNITS_PER_METER = 106.5` (`psx_track_common.py`). C'est une estimation (longueur de lap documentée / longueur brute de spline). Surcharger avec `--units-per-meter` si une meilleure constante apparaît, ou `1.0` pour rester en unités PSX brutes.
- **Winding PRM** : le rendu original n'utilise pas l'ordre stocké. Tris = `(c2, c1, c0)` ; quads = deux tris `(c2,c1,c0)` puis `(c2,c3,c1)`. Les convertisseurs le bakent avant la correction d'axes.

---

## 4. Pipeline A — import PSX « (Track01 / Track02)

C'est le workflow à suivre pour un nouveau `TRACKNN` « complet » (mesh + ligne + flags + décor + ciel).

Préparer un dossier de travail, par exemple `_converted_tracks/track_NN/`.

### 4.1 Mesh de piste texturé

Depuis `godot/tools/psx_track/` :

```powershell
py convert_track_geometry.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRV `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRF `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.gltf `
  --library-cmp D:\code\wipeout-rewrite\wipeout\TRACKNN\LIBRARY.CMP `
  --library-ttf D:\code\wipeout-rewrite\wipeout\TRACKNN\LIBRARY.TTF `
  --flip-z
```

Produit :

- `Track_NN_mesh.gltf` + `.bin`
- `Track_NN_mesh_textures/tex_*.png` (une tuile 128×128 par id de texture réellement utilisé)

Sans `--library-*`, le script cherche `library.cmp` / `library.ttf` à côté du `.TRV` (insensible à la casse). `--no-textures` saute l'export PNG.

Contrôle : le log doit donner des indices de faces dans la plage, des normales unitaires, et un nombre de textures cohérent. **Toujours** passer `--flip-z` (le défaut CLI sans flag est un miroir vs wipeout-rewrite). Si un circuit sort encore miroir **avec** `--flip-z` sur tous les convertisseurs, ne pas improviser un autre axe : s'arrêter et diagnostiquer.

### 4.2 Ligne centrale IA

```powershell
py convert_track_sections.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRS `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\track_NN_curve.json `
  --flip-z
```

Le script suit `section.next` depuis `--start` (défaut 0) jusqu'à boucler. Les branches `junction` sont ignorées (une seule racing line, consommée par `track_center_line.gd`).

JSON produit :

```json
{
  "points": [[x, y, z], ...],
  "closed": true,
  "section_flags": [["jump"], [], ...],
  "source_object": "TRACK.TRS (section 0)"
}
```

Si `closed=false`, le parcours n'est pas revenu au départ : essayer un autre `--start` ou inspecter les jonctions.

### 4.3 Flags de gameplay

```powershell
py convert_track_face_flags.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRV `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\TRACK.TRF `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\track_NN_face_flags.json `
  --flip-z
```

Exporte uniquement :

- `FACE_PICKUP_LEFT` / `FACE_PICKUP_RIGHT` → `pickup_pads` (`side`: `left`/`right`)
- `FACE_BOOST` → `boost_pads`
- `FACE_START_GRID` → `start_grid`

Chaque entrée a `face_index` et `center` (moyenne des 4 sommets du quad, même espace que le mesh). TRACK01 n'a aucune face `START_GRID` (la grille est ailleurs côté moteur original, `start_line_pos`).

### 4.4 Décor et ciel

```powershell
py convert_track_scenery.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SCENE.PRM `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SCENE.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_scene.gltf `
  --flip-z

py convert_track_scenery.py `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SKY.PRM `
  D:\code\wipeout-rewrite\wipeout\TRACKNN\SKY.CMP `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_sky.gltf `
  --flip-z
```

Les origines PRM sont bakées dans les sommets (un mesh statique combiné). Sprites (`TSPR`/`BSPR`), splines et lumières sont parsés pour rester alignés sur le flux binaire, mais ne génèrent pas de géométrie.

Contrôle de parse : la boucle doit atterrir exactement en fin de fichier, et le max des indices de texture doit valoir `nombre d'entrées CMP - 1`.

### 4.5 Ré-export Blender → GLB

Le glTF Python référence des PNG externes. Godot importe mieux un `.glb` autonome. Pour **chaque** glTF (mesh, scene, sky) :

```powershell
blender --background --python D:\code\wipeout-rewrite\godot\tools\blender\convert_track_mesh.py -- `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.gltf `
  D:\code\wipeout-rewrite\_converted_tracks\track_NN\Track_NN_mesh.glb
```

Répéter pour `Track_NN_scene.gltf` et `Track_NN_sky.gltf`. Ne pas fusionner les trois en un seul GLB : la scène Godot les instance séparément (collisions uniquement sur le mesh de piste).

### 4.6 Copie dans le projet Godot

Destination : `godot/src/assets/tracks/Track_NN/`

Fichiers à copier (écraser **en place** si le circuit existe déjà, pour conserver UID / `.import`) :

- `Track_NN_mesh.glb`
- `Track_NN_scene.glb`
- `Track_NN_sky.glb`
- `track_NN_curve.json`
- `track_NN_face_flags.json`

Puis forcer un réimport headless **avant** d'écrire des `ext_resource` UID dans un `.tscn` neuf :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

Les UID se lisent ensuite dans les fichiers `*.glb.import` (`uid="uid://..."`). Un UID périmé dans le `.tscn` continue de résoudre l'ancien asset même si le `path=` a été mis à jour.

---

## 5. Pipeline B — courbe Blender (Track12 et pistes « artisanales »)

Utilisé quand la ligne IA n'est **pas** extraite de `TRACK.TRS`, mais d'un `.blend` (cas historique de Track12 : mesh + courbe indépendants).

**Ne pas exporter la courbe en glTF.** Un objet Curve Blender sans `bevel_depth` / `extrude` devient un `Node3D` vide (0 mesh, 0 accessor). Godot n'en crée ni `Path3D` ni géométrie.

Export direct :

```powershell
blender --background chemin\vers\track_curve.blend --python D:\code\wipeout-rewrite\godot\tools\blender\export_track_curve.py -- `
  D:\code\wipeout-rewrite\godot\src\assets\tracks\Track_NN\track_NN_curve.json `
  16
```

- résolution par segment Bezier : `16` par défaut ;
- 3ᵉ argument optionnel : nom d'objet Curve si plusieurs courbes dans le `.blend` ;
- conversion d'axes Blender Z-up → Godot Y-up : `(x, y, z) → (x, z, -y)` ;
- splines `BEZIER` (échantillonnées) et `POLY` (points bruts, handles synthétisés côté reimport) sont supportées.

Inspection inverse (JSON → `.blend`) :

```powershell
blender --background --python D:\code\wipeout-rewrite\godot\tools\blender\import_track_curve.py -- `
  track_NN_curve.json track_NN_curve.blend TrackCenterLine
```

Pour ce type de piste, `ShipSpawn.y` n'est **pas** `point0.y + 2`. Il faut un raycast (ou une mesure) contre le mesh : Track12 a un offset ≈ 3.14 m pour une courbe à y = 0.

---

## 6. Câblage de la scène Godot

Modèle de référence : `godot/src/scenes/Track01.tscn` / `Track02.tscn`.

Arbre attendu :

```text
TrackNN (Node3D + TrackMeshCollider)
├── TrackMesh          instance de Track_NN_mesh.glb
├── Scenery            instance de Track_NN_scene.glb   (visuel seul)
├── Sky                instance de Track_NN_sky.glb     (visuel seul)
├── CenterLine         Path3D + track_center_line.gd
│                      source_json = res://assets/tracks/Track_NN/track_NN_curve.json
├── GameplayZones      Node3D + track_gameplay_zones.gd
│                      source_json = res://assets/tracks/Track_NN/track_NN_face_flags.json
└── ShipSpawn          Marker3D
```

`TrackMeshCollider` ne touche que `TrackMesh` (`track_mesh_path` par défaut). Il :

- crée un `StaticBody3D` / `CollisionShape3D` par `MeshInstance3D` via `create_trimesh_shape()` ;
- active `shape.backface_collision = true` (indispensable : une hull convexe gonfle hors du mesh et déclenche de faux contacts muraux dans la voie) ;
- duplique les matériaux en `CULL_DISABLED` (murs vus de l'intérieur).

`CenterLine` charge le JSON dans `_ready()`. Si le `Curve3D` est déjà peuplé en éditeur, le JSON n'est pas relu.

`GameplayZones` au `_ready()` :

- `boost_pads` → `TrackBoostPad` (`Area3D`, impulsion unique) ;
- `pickup_pads` / `start_grid` → `Marker3D` (ancres, pas encore de ramassage d'armes).

### 6.1 Calcul de `ShipSpawn` (pistes issues de `convert_track_sections.py`)

Transform **yaw-only** (pas de pitch/roll) à partir des **deux premiers points** de la courbe JSON :

1. `forward = normalize((p1.x - p0.x, 0, p1.z - p0.z))` — le Δy entre p0 et p1 est ignoré pour l'orientation.
2. `basis.z = -forward`, `basis.y = (0, 1, 0)`, `basis.x = UP.cross(basis.z)`.
3. Origine : XZ = p0.xz exactement ; **Y = p0.y + 2.0** (clairance hover fixe). Ce +2.0 ne vaut que parce que `convert_track_sections.py` bake déjà l'altitude réelle des sections.

Toujours reproduire le `Transform3D` publié de Track01 à partir de **son** JSON avant de faire confiance à une nouvelle piste.

### 6.2 Piège `Transform3D` dans un `.tscn`

Le littéral `Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` est **row-major**. Si `basis.x = (x1,x2,x3)`, `basis.y = (y1,y2,y3)`, `basis.z = (z1,z2,z3)` :

```text
Transform3D(x1, y1, z1,  x2, y2, z2,  x3, y3, z3,  ox, oy, oz)
```

Écrire les colonnes comme des triplets consécutifs produit la **transposée** (inverse d'une rotation), typiquement ~90° d'erreur de cap pour un heading à 45°. Vérification empirique : `Transform3D(1,2,3, 4,5,6, 7,8,9, ...)` charge `basis.x = (1,4,7)`.

Ne pas arrondir la base à 5 décimales : Godot 4.6 exige une base normalisée (`get_rotation_quaternion()` plante sinon). Émettre au moins ~12 décimales, locale invariante (point décimal, pas de virgule FR).

---

## 7. Validation avec `godot/src/tools`

Tous ces scripts s'exécutent depuis le projet Godot (`--path godot/src`). Ils `extends SceneTree` : un `extends Node` avec `_ready()` échoue (`doesn't inherit from SceneTree or MainLoop`).

Godot headless bufferise stdout/stderr. Pour ne pas perdre les `print`, le script doit appeler `quit()` lui-même. Ne pas tuer le process.

Les `_ready()` des enfants ajoutés dans `_initialize()` ne sont **pas** garantis à la fin de `_initialize()` (ex. `CenterLine.curve` encore `null`). Les validateurs attendent 2–3 `physics_frame` avant de lire la scène.

Ne pas lancer deux validateurs en parallèle sur le même projet (état runtime partagé).

### 7.1 Inspecter un GLB / une scène fraîchement importée

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/inspect_scene.gd -- res://assets/tracks/Track_NN/Track_NN_mesh.glb
```

Contrôler : présence de `MeshInstance3D`, `surfaces > 0`, AABB non nulle. Sur un GLB de courbe mal exporté, on ne verrait qu'un nœud vide — d'où le JSON, pas le glTF, pour la racing line.

### 7.2 Alignement vaisseaux / ligne centrale

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/inspect_ai_track_alignment.gd
```

Charge `main.tscn`, attend une frame physique, imprime pour `Ship` / `ShipAI1` / `ShipAI2` : position, offset sur la courbe, erreur latérale XZ, direction. Utile après un recâblage de spawn ou un nouveau JSON de courbe.

### 7.3 Murs de rive (Track01)

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/validate_track_side_walls.gd
```

Place un vaisseau sur `Track01.tscn`, vérifie que le sol sous le spawn n'est pas classé mur, pousse vers l'étagère droite (~18 m) et exige un rebond (pas une montée > 3,5 m). C'est le filet de sécurité du collider trimesh + backface.

Le script est **câblé sur Track01**. Pour une autre piste : dupliquer / paramétrer `TRACK_SCENE` et le décalage latéral (largeur de voie).

### 7.4 Champ IA complet

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/validate_ai_field.gd
```

Attend 48 frames physiques sur `main.tscn` : 8 vaisseaux (7 IA + 1 joueur), `center_line` peuplée, au moins 5 IA en mouvement, rangs 1–8 uniques.

### 7.5 Hors import, mais souvent oublié

`setup_input_map.gd` **n'écrit les bindings dans `project.godot` que s'il est réellement exécuté** :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src `
  -s res://tools/setup_input_map.gd
```

Éditer le `.gd` sans le lancer ne met pas à jour `[input]`.

---

## 8. Checklist d'un nouveau circuit

1. Identifier `TRACKNN` ↔ nom in-game via `game.c` / `TRACK.INF`.
2. Convertir géométrie, sections, face flags, scene, sky **avec `--flip-z`** et le même `--units-per-meter` sur chaque convertisseur.
3. Ré-exporter les 3 glTF en GLB via Blender headless.
4. Copier GLB + JSON dans `godot/src/assets/tracks/Track_NN/` (même nom de fichier si remplacement).
5. `godot --headless --path godot/src --import` puis lire les UID dans les `.import`.
6. Créer / mettre à jour `scenes/TrackNN.tscn` (arbre §6).
7. Calculer `ShipSpawn` (formule yaw-only + 2 m si courbe TRS ; raycast si courbe Blender).
8. Vérifier le littéral `Transform3D` (row-major, ≥12 décimales, `basis.y = (0,1,0)`).
9. `inspect_scene.gd` sur les GLB ; `inspect_ai_track_alignment.gd` une fois le circuit branché dans `main.tscn`.
10. Adapter / relancer `validate_track_side_walls.gd` si la voie a des edge shelves.
11. Relancer `validate_ai_field.gd` si le circuit devient la piste de `main.tscn`.

---

## 9. Limites connues

- Les flags `section_flags` (`jump`, jonctions) sont exportés mais pas consommés par Godot (rescue droid / branches hors scope).
- Pads d'armes et grille de départ : marqueurs seulement.
- Boost : impulsion unique à l'entrée d'une boîte, pas la poussée continue par face du C original.
- Ciel : pas de `sky_y_offset` par circuit (`game.c`).
- Décor / ciel : pas de collider (voulu) ; pas de `CULL_DISABLED` automatique (faces éventuellement transparents selon l'angle).
- Billboards / lumières / splines PRM : parsés, non meshés.
- `DEFAULT_UNITS_PER_METER = 106.5` reste une estimation ; un recoupement par dénivelé donne ~33.3 (écart ~3.2× non résolu).
- Headless : `get_viewport().get_texture()` est nul — pas de screenshot. Valider par télémétrie de positions sur plusieurs `physics_frame`.

---

## 10. Références internes

- Audits d'import Track01 : `godot/docs/.transactional/26-08-25-01/audit/`
- Diagnostic courbe glTF vide (Track12) : `godot/docs/.transactional/26-08-22-01/draft/spline_centrale_piste_01.md`
- Parseurs C de référence : `src/wipeout/track.c`, `src/wipeout/image.c`, `src/wipeout/object.c`, `src/wipeout/scene.c`
