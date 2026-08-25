# Implémentation — décor (sky/scene), flags pickup/boost/start-grid, et ré-import complet de TRACK01

Suite à [track01_import_gaps_audit.md](track01_import_gaps_audit.md), voici ce qui a été implémenté pour combler les manques identifiés (section 2) et l'état du circuit `Track_01` après ré-import.

## 1. Nouveaux convertisseurs Python

- [convert_track_scenery.py](../../../../tools/psx_track/convert_track_scenery.py) — parse `SCENE.PRM`/`SKY.PRM` (+ `SCENE.CMP`/`SKY.CMP`) et exporte un mesh texturé OBJ/glTF. Format `.PRM` rétro-ingénieré à partir de `object.c`/`object.h` du moteur original (vérifié contre le dépôt GitHub `phoboslab/wipeout-rewrite` au commit exact utilisé localement), avec parseur ajouté dans [psx_track_common.py](../../../../tools/psx_track/psx_track_common.py) (`parse_prm`, types de primitives F3/FT3/G3/GT3/LSx.../TSPR/SPLINE/lumières, ordre de rendu des sommets, décodage couleur `rgba_from_u32`).
- [convert_track_face_flags.py](../../../../tools/psx_track/convert_track_face_flags.py) — extrait de `TRACK.TRF` les faces `FACE_PICKUP_LEFT/RIGHT`, `FACE_BOOST`, `FACE_START_GRID` avec leur centre en espace monde, vers un JSON.
- Refactor : `Face`/`parse_trv`/`parse_trf`/constantes `FACE_*` déplacés dans `psx_track_common.py` pour être partagés entre `convert_track_geometry.py` et `convert_track_face_flags.py`.

## 2. Pipeline d'import complet (ré-exécuté pour TRACK01)

1. `convert_track_geometry.py` → mesh texturé (`Track_01_mesh.gltf` + PNGs)
2. `convert_track_sections.py` → ligne de course (`track_01_curve.json`)
3. `convert_track_face_flags.py` → flags de gameplay (`track_01_face_flags.json`) : 13 pads d'armes, 20 pads de boost, 0 face de grille de départ (probablement gérée via `start_line_pos` dans `game.c`, pas via un flag de face)
4. `convert_track_scenery.py` (x2) → décor (`Track_01_scene.gltf`, 264 objets/8489 triangles/39 textures) et ciel (`Track_01_sky.gltf`, 336 triangles)
5. [convert_track_mesh.py](../../../../tools/blender/convert_track_mesh.py) (Blender headless) → conversion des 3 glTF en `.glb` autonomes (textures embarquées)
6. Copie des 5 fichiers finaux dans [src/assets/tracks/Track_01](../../../../src/assets/tracks/Track_01)

## 3. Intégration dans le projet Godot

- Nouveau script [track_gameplay_zones.gd](../../../../src/scripts/track_gameplay_zones.gd) : charge `track_01_face_flags.json` et instancie des `Marker3D` groupés (`PickupPads`, `BoostPads`, `StartGrid`) aux positions des faces correspondantes. Aucune logique de gameplay attachée (aucun système de ramassage/boost n'existait déjà dans le projet) — ce sont de simples ancres pour un futur système.
- [Track01.tscn](../../../../src/scenes/Track01.tscn) : ajout des nœuds `Scenery` (décor), `Sky` et `GameplayZones`, aux côtés de `TrackMesh`/`CenterLine` existants. `TrackMeshCollider` reste scopé au seul nœud `TrackMesh` (son `track_mesh_path` par défaut), donc le décor et le ciel ne génèrent pas de collisions physiques — comportement voulu, ce sont des éléments visuels.

## 4. Validation

- Les 3 glTF générés s'importent/exportent proprement via Blender headless.
- Réimport headless de l'éditeur Godot : aucune erreur sur les nouveaux `.glb`.
- [Track01Test.tscn](../../../../src/scenes/tests/Track01Test.tscn) rejoué en headless avec la piste complète (mesh + décor + ciel + zones) : code de sortie 0, aucune erreur ni avertissement.

## 5. Limites connues / suites possibles

- Le ciel n'applique pas le `sky_y_offset` par circuit présent dans `game.c` (ajustement de rendu propre au moteur original, non nécessaire pour une géométrie statique mais pourrait affiner les proportions).
- Les meshes de décor n'ont pas le traitement double-face (`cull_mode` désactivé) appliqué à `TrackMesh` par `TrackMeshCollider` ; à ajouter si des faces apparaissent transparentes dans un sens de vue.
- Les billboards (`TSPR`/`BSPR`), splines et lumières du format `.PRM` sont parsés (pour garder l'alignement du flux binaire) mais ne produisent pas de géométrie — hors scope pour cette passe.
- `FACE_START_GRID` n'a donné aucun résultat pour TRACK01 ; à confirmer si une autre piste en possède, sinon la grille de départ est probablement pilotée ailleurs (`start_line_pos` par circuit).
