# Pistes 1 et 2 — import en miroir (même bug d’axes que Track03)

## Résumé

Track01 (Terramax) et Track02 (Altima VII Venom) avaient le même miroir que Track03 vs wipeout-rewrite : gauche/droite inversés, pubs à l’envers.

Cause identique : import initial **sans** `--flip-z` → `(x, -y, z)` (réflexion). `--flip-z` → `(x, -y, -z)` (rotation).

---

## Correctif

Pipeline A complet relancé **avec `--flip-z` sur tous les convertisseurs** (géométrie, sections, face flags, scenery, sky), Blender glTF→GLB, copie in-place, `--import`, recalcul `ShipSpawn`.

Spawns (sonde, ≥12 décimales, row-major) :

Track01 :

```
Transform3D(0.886275624587, 0.000000000000, 0.463158198958, 0.000000000000, 1.000000000000, 0.000000000000, -0.463158198958, 0.000000000000, 0.886275624587, -312.431924882629, 22.093896713615, 485.399061032864)
```

`p0.z` : `-485.40` → `+485.40`.

Track02 (identique à Track03 après flip, même layout Altima) :

```
Transform3D(0.769154104831, 0.000000000000, -0.639063348207, -0.000000000000, 1.000000000000, 0.000000000000, 0.639063348207, 0.000000000000, 0.769154104831, 243.267605633803, 3.164319248826, 603.586854460094)
```

`p0.z` : `-603.59` → `+603.59`.

UIDs GLB inchangés (écrasement in-place).

---

## Fichiers

### Track01

- `godot/src/assets/tracks/Track_01/Track_01_mesh.glb`
- `godot/src/assets/tracks/Track_01/Track_01_scene.glb`
- `godot/src/assets/tracks/Track_01/Track_01_sky.glb`
- `godot/src/assets/tracks/Track_01/track_01_curve.json`
- `godot/src/assets/tracks/Track_01/track_01_face_flags.json`
- `godot/src/scenes/Track01.tscn` (`ShipSpawn`)

### Track02

- `godot/src/assets/tracks/Track_02/Track_02_mesh.glb`
- `godot/src/assets/tracks/Track_02/Track_02_scene.glb`
- `godot/src/assets/tracks/Track_02/Track_02_sky.glb`
- `godot/src/assets/tracks/Track_02/track_02_curve.json`
- `godot/src/assets/tracks/Track_02/track_02_face_flags.json`
- `godot/src/scenes/Track02.tscn` (`ShipSpawn`)

Scratch : `_converted_tracks/track_01/`, `_converted_tracks/track_02/`.

---

## Validation

Sériel, Godot 4.6.1 headless :

| Script | Résultat |
| --- | --- |
| `inspect_scene.gd` Track01 mesh/scene/sky | MeshInstance3D, surfaces > 0, AABB non nulle |
| `inspect_scene.gd` Track02 mesh/scene/sky | idem |
| `validate_track_side_walls.gd` (Track01) | OK (`saw_wall=true`, `climb=0.0`) |

`--flip-z` est désormais le flag **par défaut** du pipeline A pour Track01 / Track02 / Track03 (skill + `workflow_import_circuit.md`).

---

## Notes

- Ne pas comparer un spawn Track01 « historique » d’avant le flip : le `Transform3D` publié a changé (Z nié).
- `main.tscn` reste sur Track12 ; `validate_ai_field` / `inspect_ai_track_alignment` non relancés.
