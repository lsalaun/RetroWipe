# Piste 3 — surface pentue classée comme mur latéral

## Résumé

Sur Track03 (Altima VII Rapier), dès que la piste devient trop pentue / relevée, le sol de course était traité comme un mur latéral. Le hover ignorait la surface, les probes de mur renvoyaient le vaisseau, et celui-ci ne pouvait plus avancer.

Cause : `_is_side_wall_normal()` ne regardait que `|normale · droite_horizontale|`. Ça marche sur une piste quasi plate (Track01 : lat max ~0.14). Sur le virage relevé de Track03 (~offset 5520–5760), le sol a encore `n.y ≈ 0.83` mais une composante latérale monde `≥ 0.45` — le même seuil que les étagères de rive (~40°, lat ~0.70).

---

## Symptôme

- Circuit : Track03 (`res://scenes/Track03.tscn`)
- Zone : rampe / virage relevé, ligne centrale ~5520–5760 m
- Comportement : le vaisseau « se cogne » contre le sol et s’arrête
- Mesure avant correctif : 60 faux murs sur 2197 échantillons de ligne centrale (`max_lat=0.528`, `min_ny=0.44`)

Track01 n’était pas touché (`false_walls=0`, `max_lat=0.143`).

---

## Correctif

Dans `wipeout_ship.gd` :

1. Échantillonner la normale du **sol sous la ligne centrale** (`_track_floor_normal`).
2. Si `|normale · sol_ligne| ≥ wall_floor_align_min` (0.82), c’est encore la surface de course, pas un mur.
3. Construire `_track_right_dir` avec `tangente × normale_sol`, pas avec l’UP monde — la « droite de piste » suit le devers.
4. Le hover n’applique plus le filtre `|n.y| < hover_min_normal_y` aux faces déjà alignées avec le sol de course.

Les étagères de rive restent des murs : elles ne collent pas à la normale du sol de la ligne (`|n · floor|` bas, lat ~0.70).

---

## Fichiers ajoutés / modifiés

### Modifiés

- `godot/src/scripts/wipeout_ship.gd`

### Ajoutés

- `godot/src/tools/inspect_track_wall_classification.gd` — échantillonne sol vs heuristique mur le long d’une courbe
- `godot/src/tools/validate_track03_slope.gd` — pose un vaisseau sur la rampe Track03 et exige une avancée sans impact mural

---

## Validation

```text
godot --headless --path godot/src -s res://tools/inspect_track_wall_classification.gd -- res://scenes/Track03.tscn
godot --headless --path godot/src -s res://tools/inspect_track_wall_classification.gd -- res://scenes/Track01.tscn
godot --headless --path godot/src -s res://tools/validate_track_side_walls.gd
godot --headless --path godot/src -s res://tools/validate_track03_slope.gd
```

Résultats observés :

| Check | Résultat |
|---|---|
| Track03 ligne centrale | `false_walls=0`, `max_lat=0.062` (était 60 / 0.528) |
| Track03 étagères | `shelf_walls=1617` / `shelf_hits=1901` (toujours des murs) |
| Track01 ligne centrale | `false_walls=0` |
| Track01 étagères (poussée) | `validate_track_side_walls: OK` |
| Track03 rampe offset 5600 | `progress=33.0`, `wall_hits=0` |

---

## Retuning

- `wall_floor_align_min` (défaut 0.82) : trop bas → une étagère peu pentue peut passer pour du sol ; trop haut → un devers fort redevient un mur.
- `wall_lateral_min` (0.45) inchangé : toujours le seuil « pointe en travers de la voie » une fois le sol de course écarté.
