# Audit de fidélité — Physique du vaisseau (original vs Godot)

Comparaison entre la physique originale du vaisseau (`src/wipeout/ship_player.c`, `src/wipeout/ship.c`, `src/wipeout/ship.h`) et le port Godot (`godot/src/scripts/wipeout_ship.gd`).

## Verdict

Le script Godot est une **réinterprétation stylisée**, pas un portage littéral. Plusieurs formules-clés sont reprises (et documentées comme telles en commentaire), mais plusieurs mécaniques physiques importantes de l'original sont simplifiées ou absentes.

## Fidèlement reproduit (formule équivalente)

| Mécanique originale | Godot | Fidélité |
|---|---|---|
| `track_repulsion = 4096 * (MAGNET * FLOAT/height - MAGNET)` (`ship_player.c:359`) | `repulsion = track_magnet * (hover_height/height - 1.0) * hover_force` (`wipeout_ship.gd:183`) | ✅ même forme mathématique (répulsion inverse à la hauteur) |
| `angular_acceleration.z += (angular_velocity.y - 0.5*angular_velocity.z)*30` (`ship_player.c:422`) | `roll_accel = ... + roll_yaw_gain*yaw_velocity - roll_spring_damping*roll_rate` (`wipeout_ship.gd:266`) | ✅ terme repris, mais **augmenté** d'un ressort vers un `bank_target` (steer/brake) qui n'existe pas dans l'original |
| Contre-braquage (rappel du volant côté opposé à double vitesse) dans `ship_player_update_race` | `turn_reverse_boost` appliqué si `steer` s'oppose à `yaw_velocity` | ✅ idée conservée, formule simplifiée (pas de courbe `analog_response`/`turn_target`) |
| `SHIP_THRUST_RATE` / `SHIP_THRUST_FALLOFF` (montée/chute de poussée) | `thrust_ramp` / `thrust_falloff` | ✅ même principe |

## Approximé ou remplacé par un mécanisme différent

- **Grip / dérapage** : l'original n'a pas de friction latérale séparée. Il applique `acceleration += (forward_velocity - velocity) / (skid + brake*0.25)` (`ship_player.c:365`) — un terme qui ramène progressivement la vitesse vers l'axe du vaisseau, piloté par l'attribut `skid` propre à chaque pilote/classe. Godot fait un calcul conceptuellement proche mais différent : `velocity -= right * lateral_speed * lateral_friction * delta` (`wipeout_ship.gd:200`) — pas d'attribut `skid` par vaisseau, pas de mélange avec `forward_velocity`.
- **Traînée globale** : l'original soustrait `velocity / resistance` sur les 3 axes (`ship_player.c:367`). Godot ne freine que la composante planaire (`planar_drag`) et amortit la verticale séparément (`hover_damping`) — comportement similaire en apparence, formule différente.
- **Rebond au sol** : l'original a une logique explicite de rebond dur si `height <= 0` (réflexion de vélocité *2, atténuation 0.875) puis répulsion progressive si `height < 30` (`ship_player.c:339-347`). Godot n'a aucun équivalent — il compte sur les raycasts de hover + `move_and_slide()` du moteur physique.
- **Alignement du nez sur la piste** (torque de tangage basé sur la différence de hauteur nez/coque, `nose_height`, `ship_player.c:370-377`) : absent. Godot aligne l'assiette par un simple `slerp` de la base vers la normale de hover (`_update_orientation`), un résultat visuellement correct mais sans base physique commune.
- **Collision avec les murs** : l'original distingue collision "nez" vs "aile" avec calcul d'angle d'impact et magnitude proportionnelle à la vitesse (`ship_resolve_nose_collision` / `ship_resolve_wing_collision` dans `ship.c`). Godot utilise un rebond générique (`velocity.bounce(normal) * wall_bounce_damping`) avec un `wall_turn_kick` fixe, indépendant de la vitesse ou du point d'impact (`wipeout_ship.gd:232-240`).
- **Frein différentiel (airbrakes)** : l'original les utilise pour moduler la `resistance`, le `track_repulsion` (via le facteur brake) et pour tourner via `angle.y += brake_dir * speed * ...`. Godot freine directement la vitesse avant (`velocity -= forward * min(forward_speed, ...)`) et ajoute du lacet proportionnel à la vitesse planaire — logique différente bien que l'effet gameplay (virage en freinant d'un côté) soit similaire.

## Absent (non porté du tout)

- **Poussée arrière** : `Input.get_axis` permet un `throttle < 0` qui freine activement le vaisseau (`wipeout_ship.gd:133`). Dans l'original, `A_THRUST` est unidirectionnel (`thrust_mag` clampé `[0, thrust_max]`), il n'y a pas de poussée arrière.
- **Collision vaisseau-vaisseau** avec conservation de quantité de mouvement (`ship_collide_with_ship`, échange de vitesse pondéré par la masse) : totalement absent du script.
- **Boost pads** (`FACE_BOOST`), **sections de saut** (`SECTION_JUMP`), **jonctions** (`SECTION_JUNCTION`) : aucune référence dans le script.
- **Sauvetage (rescue)** : l'original recalcule la distance au rail central de la piste et retéléporte vers la dernière section valide ou l'atterrissage d'un saut. Godot fait un simple timeout générique (`airborne_time > rescue_delay`) + un seuil `y < -25`, bien plus simpliste.
- **Attributs par pilote/équipe** (`mass`, `thrust_max`, `skid`, `turn_rate`, `turn_rate_max`, `resistance` définis par équipe/classe dans les données du jeu) : dans Godot ce sont des `@export` uniques sur le nœud, pas de système de profils par vaisseau/pilote comme `def.teams[team].attributes[...]`.

## Conclusion

Le script Godot capture l'esprit de la physique originale (poussée, hover magnétique, lacet avec contre-braquage, roulis dérivé du lacet) et documente honnêtement ses emprunts en commentaire ("ported from..."). Ce n'est pas une reproduction fidèle : le grip/dérapage, la traînée globale, les collisions (murs et vaisseau-vaisseau), les boosts, jonctions/sauts, et le système de secours sont soit simplifiés soit absents. Pour une fidélité stricte au modèle original, il manque en particulier le terme `skid`/`forward_velocity` blending et la logique de collision par face (nez/aile).
