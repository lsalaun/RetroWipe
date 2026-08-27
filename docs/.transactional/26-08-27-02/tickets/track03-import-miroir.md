# Piste 3 — import en miroir (gauche/droite + pubs à l’envers)

## Résumé

Track03 (Altima VII Rapier) importé dans Godot était le **miroir** du circuit dans wipeout-rewrite : gauche/droite inversés, panneaux publicitaires lisibles à l’envers.

Cause : le premier import a utilisé le défaut des convertisseurs `(x, -y, z)`. Nier **un seul** axe (Y) est une **réflexion**. `--flip-z` produit `(x, -y, -z)` (deux axes) : rotation, pas miroir. Le skill le prescrit quand le premier mesh est visuellement mirroir. Track01 / Track02 restent sans `--flip-z`.

---

## Symptôme

- Circuit : Track03 (`res://scenes/Track03.tscn`) vs wipeout-rewrite TRACK03
- Gauche et droite de piste inversées
- Décors SCENE (pubs) comme vus dans un miroir
- Courbe / pads / mesh cohérents **entre eux** (même défaut) — le bug n’était pas un décalage mesh vs courbe

---

## Diagnostic

`make_axis_transform` dans `godot/tools/psx_track/psx_track_common.py` :

- défaut : `(x, -y, z)` + inversion de winding (`reverse_winding = True`)
- `--flip-z` : `(x, -y, -z)` + winding d’origine (`reverse_winding = False`)

Le moteur C (`render_set_view`) n’applique pas ce miroir monde : il pose la caméra (yaw + π, translation inversée) sur les vertices PSX bruts. Godot a besoin d’un changement d’axes **pair** pour +Y up sans réflexion.

Les UV SCENE ne sont pas le bug : un texte à l’envers sur des quads 3D suit le miroir des positions, pas un flip U isolé.

---

## Correctif

Re-import Pipeline A **avec `--flip-z` sur tous les convertisseurs** (géométrie, sections, face flags, scenery, sky), puis Blender glTF→GLB, copie in-place, `--import`, recalcul `ShipSpawn`.

Spawn (sonde, ≥12 décimales, row-major) :

```
Transform3D(0.769154104831, 0.000000000000, -0.639063348207, -0.000000000000, 1.000000000000, 0.000000000000, 0.639063348207, 0.000000000000, 0.769154104831, 243.267605633803, 3.164319248826, 603.586854460094)
```

`p0.z` passe de `-603.59` à `+603.59`. Track01 reproduit toujours son `Transform3D` publié (contrôle de la sonde).

---

## Fichiers ajoutés / modifiés

### Modifiés

- `godot/src/assets/tracks/Track_03/Track_03_mesh.glb`
- `godot/src/assets/tracks/Track_03/Track_03_scene.glb`
- `godot/src/assets/tracks/Track_03/Track_03_sky.glb`
- `godot/src/assets/tracks/Track_03/track_03_curve.json`
- `godot/src/assets/tracks/Track_03/track_03_face_flags.json`
- `godot/src/scenes/Track03.tscn` (`ShipSpawn` uniquement ; UIDs GLB inchangés)

Scratch : `_converted_tracks/track_03/` (mêmes noms, `--flip-z`).

---

## Validation

Sériel, Godot 4.6.1 headless, `--path godot/src` :

| Script | Résultat |
| --- | --- |
| `inspect_scene.gd` mesh | MeshInstance3D, 20 surfaces, AABB non nulle |
| `inspect_scene.gd` scene | 43 surfaces, AABB non nulle |
| `inspect_scene.gd` sky | 1 surface, AABB non nulle |
| `inspect_track_wall_classification.gd` | `false_walls=0` |
| `validate_track03_slope.gd` | OK (`progress=33`, `wall_hits=0`) |
| `validate_track03_descent.gd` | OK (`drop=88.6`, `spawn_dist=1096`) |

Contrôle visuel restant : comparer pubs / rive gauche-droite avec wipeout-rewrite en jeu.

---

## Notes

- Ne **pas** improviser un scale/axe dans Blender (`export_yup=True` seulement).
- Track01 / Track02 ont le même miroir : re-importés avec `--flip-z` (voir `track01-02-import-miroir.md`). Le flag est le défaut du pipeline A pour ces trois circuits.
- Convertisseurs déjà alignés ; le trou était le **flag omis**, pas un parser UV.
