# Implémentation — script d'import GLB pour les vaisseaux (convert_ships.py)

Suite à [track01_boost_pads_implementation.md](track01_boost_pads_implementation.md), un nouveau script convertit les modèles de vaisseaux PSX (`D:\code\wipeout-rewrite\wipeout\COMMON`) en mesh Godot/Blender.

## 1. Nouveau script

[convert_ships.py](../../../../tools/psx_track/convert_ships.py) — convertit `COMMON/ALLSH.PRM` + `COMMON/ALLSH.CMP` (modèles visuels des 8 vaisseaux) en un fichier OBJ/glTF texturé **par vaisseau**. Fonctionne aussi sur `ALCOL.PRM`/`ALCOL.CMP` (modèles de collision bas-poly utilisés par `ship_intersects_ship()`), même format binaire.

Usage :
```
python convert_ships.py COMMON/ALLSH.PRM COMMON/ALLSH.CMP out_dir/
python convert_ships.py COMMON/ALCOL.PRM COMMON/ALCOL.CMP out_dir/ --format obj
```

## 2. Particularité par rapport au décor (`convert_track_scenery.py`)

Vérifié dans `ship.c` : `object_draw()` est toujours appelé avec la transform live du vaisseau (`&self->mat`), jamais dérivée de `object->origin`. Contrairement aux objets de décor (`SCENE.PRM`/`SKY.PRM`, où `origin` est bien appliqué par `scene_load()`), `convert_ships.py` exporte donc chaque modèle en **espace local** (pas de translation par `origin`), prêt à être parenté sous la racine d'un vaisseau dans Godot.

## 3. Refactor : logique partagée avec `convert_track_scenery.py`

Extrait dans [psx_track_common.py](../../../../tools/psx_track/psx_track_common.py) :
- `emit_prm_object_triangles` — triangulation d'un objet PRM (ordre de sommets `object_draw()`, UV normalisées, couleurs par sommet).
- `export_flat_textures` — export PNG depuis une liste CMP plate (pas d'assemblage de tuiles, contrairement à `LIBRARY.CMP`).
- `write_prm_obj` / `write_prm_gltf` — écriture OBJ+MTL / glTF avec `COLOR_0` par sommet.

`convert_track_scenery.py` a été mis à jour pour réutiliser ces fonctions au lieu de ses propres copies.

## 4. Validation

- Ré-exécution de `convert_track_scenery.py` après refactor : mêmes résultats qu'avant (264 objets, 8489 triangles, 40 groupes de matériaux) — comportement inchangé.
- `convert_ships.py` sur `COMMON/ALLSH.PRM` (données réelles) : 8 vaisseaux détectés, **nommés directement dans les données PSX** (`sophia`, `solaar`, `jacko`, `chang`, `arian`, `arial`, `anasta`, `Dekka` — correspondant aux pilotes de `game.c`), chacun avec ses textures propres (131 à 186 triangles, 10-13 textures/vaisseau).
- Import/export Blender headless réussi sur un des glTF générés (`sophia.gltf` → `.glb`).
- Texture d'un vaisseau vérifiée visuellement (motif de coque plausible).

## 5. Limites / suites possibles

- Pas encore intégré dans le projet Godot (pas de copie dans `src/assets/`, pas de scène instanciant les vaisseaux) — script de conversion uniquement, comme demandé.
- Les billboards/splines/lumières du format `.PRM` restent parsés mais ignorés (mêmes limites que `convert_track_scenery.py`).
- `ALCOL.PRM`/`ALCOL.CMP` (modèles de collision) non testés avec de vraies données dans cette passe, seul le format est partagé.
