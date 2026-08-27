# Piste 3 — respawn en descente (faux hors-piste)

## Résumé

Sur Track03 (Altima VII Rapier), une descente longue déclenchait un respawn du vaisseau comme s’il était sorti de piste, alors qu’il était encore sur la surface de course.

Ce n’était **pas** un seuil au point le plus bas de la piste, ni un `y` monde fixe. Le test de chute comparait le Y du vaisseau au **dernier sol** (`last_ground_height`) moins `void_fall_margin` (25 m). Si le hover lâchait au sommet, ce Y restait gelé au crest. Track03 descend ~578 m d’un seul tenant : 25 m plus bas le vaisseau est encore **sur** la ligne, mais le test le prenait pour un vide et le renvoyait au spawn.

---

## Symptôme

- Circuit : Track03 (`res://scenes/Track03.tscn`)
- Zone : descente après le crest (courbe Y max ≈ 571 m, idx ~203 → bas ≈ −6 m, idx ~269)
- Comportement : respawn / reset spawn en pleine descente
- Ancien test : `global_position.y < last_ground_height - void_fall_margin`
- Mesure : 25 m de dénivelé ~66 m de piste après le crest (idx 208, Y ≈ 541)

`rescue_delay` (timeout aérien) n’est pas en cause ici : le reset partait du test de vide, et il appelait `_reset_to_spawn()` plutôt qu’un recollage sur la ligne.

---

## Correctif

Dans `wipeout_ship.gd` :

1. `_is_in_void()` : si une `center_line` est dispo, le Y de référence est celui du **point de ligne le plus proche** (`_track_center_point.y`), pas le dernier crest. Sans courbe, fallback `last_ground_height`.
2. `_track_center_point` est mis à jour dans `_refresh_track_axes()` (même offset que les axes mur/sol).
3. Un vide confirmé appelle `_rescue_to_track()` (repose sur la ligne, un peu en arrière), plus `_reset_to_spawn()`. Le reset spawn reste pour l’input joueur.

Le `void_fall_margin` (25 m) ne change pas : il mesure maintenant « trop bas **par rapport à la piste ici** », pas « trop bas par rapport au sommet ».

---

## Fichiers ajoutés / modifiés

### Modifiés

- `godot/src/scripts/wipeout_ship.gd`

### Ajoutés

- `godot/src/tools/validate_track03_descent.gd` — pose un vaisseau 40 m sous le crest (dernier sol figé au sommet) et exige « pas void » ; puis le fait descendre et refuse un retour au spawn

---

## Validation

```text
godot --headless --path godot/src -s res://tools/validate_track03_descent.gd
godot --headless --path godot/src -s res://tools/validate_track03_slope.gd
```

Résultats observés :

| Check | Résultat |
|---|---|
| 40 m sous le crest, encore sur la ligne | `void_ok` (`on_track_y=533`, `line_y=532`, `crest_y=571`) |
| Descente réelle depuis le crest | `drop=88.48`, `spawn_dist=1096`, pas de reset spawn |
| Rampe / murs Track03 | `validate_track03_slope: OK` (inchangé) |

---

## Retuning

- `void_fall_margin` (défaut 25.0) : trop petit → un bump / un saut légitime rescue trop tôt ; trop grand → vraie chute dans le vide trop tardive.
- Sans `center_line`, le comportement reste l’ancien (Y du dernier sol).
