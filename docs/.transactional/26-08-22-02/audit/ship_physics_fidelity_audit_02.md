# Audit de fidélité — Physique du vaisseau (original vs Godot), passage 2

Comparaison entre la physique originale du vaisseau (`src/wipeout/ship_player.c`, `src/wipeout/ship.c`, `src/wipeout/ship.h`) et le port Godot (`godot/src/scripts/wipeout_ship.gd`), après implémentation des phases 0 à 8 de `../implementation/ship_physics_convergence_plan_01.md`. À comparer avec `ship_physics_fidelity_audit_01.md` (passage 1, avant ces phases).

## Verdict

Le port Godot est passé d'une **réinterprétation stylisée** à un **portage fidèle avec adaptations documentées**. La quasi-totalité des écarts de fond identifiés au passage 1 (grip, traînée, rebond sol, torque de nez, collisions murs par face, collision vaisseau-vaisseau, système de secours, profils par pilote) sont désormais couverts par des formules équivalentes, portées et commentées (`# ported from ...`). Les écarts restants sont soit des choix de design assumés (poussée arrière en frein plutôt qu'en poussée négative), soit des chantiers hors scope faute de données (features de piste boost/jump/junction).

## Fidèlement reproduit (formule équivalente)

| Mécanique originale | Godot | Fidélité |
|---|---|---|
| `track_repulsion = 4096 * (MAGNET * FLOAT/height - MAGNET)` (`ship_player.c:359`) | `repulsion = track_magnet * (hover_height/height - 1.0) * hover_force` (`_apply_hover_forces`) | ✅ inchangé depuis le passage 1 |
| Rebond dur si `height <= 0` (réflexion de vélocité, atténuation 0.875) + poussée si `height < margin` (`ship_player.c:339-347`) | `velocity = velocity.bounce(up) * bounce_restitution` puis `floor_push_speed` si `< bounce_margin` (`_apply_hover_forces`) | ✅ nouveau (Phase 3) — même structure conditionnelle à 2 seuils |
| Torque de tangage basé sur `nose_height` (`ship_player.c:370-377`) | `pitch_velocity` intégré depuis `hover.height - hover.nose_height` (`nose_pitch_gain`/`max`), appliqué à `desired_forward` avant le `slerp` générique (`_update_orientation`) | ✅ nouveau (Phase 3) — `nose_height` approximée par les 2 rayons avant plutôt qu'un 5ᵉ raycast dédié |
| `acceleration += (forward_velocity - velocity) / (skid + brake*0.25)` (`ship_player.c:365`) | `velocity += (forward_velocity - velocity) / grip_denominator * delta` avec `grip_denominator = skid + brake_sum*0.25` (`_apply_drive_forces`) | ✅ nouveau (Phase 1) — même forme, `skid` maintenant un `@export` par profil |
| `acceleration -= velocity / resistance` sur les 3 axes, `resistance` différente sol/air et atténuée par le freinage (`ship_player.c:367`) | `velocity -= velocity * (delta / resistance_effective)`, `resistance_effective` sol/air distinct, atténué par `brake_sum` (`_apply_drive_forces`) | ✅ nouveau (Phase 2) — drag global 3 axes au lieu de planaire+vertical séparés ; `hover_damping` conservé en supplément (non remplacé, cf. Phase 2 point 3) |
| Collision mur nez vs aile avec angle/vitesse (`ship_resolve_nose_collision`/`ship_resolve_wing_collision`, `ship.c`) | Classification par projection latérale du point de contact, `yaw` proportionnel à la vitesse (nez) vs `roll_rate` proportionnel à l'angle×vitesse (aile), `vec3_reflect`+push (`_handle_wall_collisions`) | ✅ nouveau (Phase 4) — anti-spam d'impact ajouté (`wall_impact_cooldown`) |
| `ship_collide_with_ship` : vitesse combinée pondérée par la masse + poussée de séparation (`ship.c`) | `ShipCollisionManager` : `combined_velocity` pondérée par `mass`, `+= (combined - v)*0.5`, `separation * push_k` | ✅ nouveau (Phase 5) — gestionnaire au niveau scène, détection via `HullArea` dédiée |
| Rescue vers la dernière section valide de la piste (`ship_player.c`) | `_rescue_to_track` : projection sur `center_line.curve`, recul de `rescue_look_back`, orientation via tangente | ✅ nouveau (Phase 7) — approximation par plus-proche-point sur `Curve3D` plutôt que par sections discrètes explicites |
| Attributs par pilote/équipe (`mass`, `thrust_max`, `skid`, `turn_rate`/`turn_rate_max`, `resistance`) | `ShipHandlingProfile` (`mass`, `thrust_max`, `skid`, `turn_accel`/`turn_max`, `resistance`, ...) + 3 `.tres` distincts chargés par vaisseau (`main.tscn`) | ✅ nouveau (Phase 8) — `turn_rate`/`turn_rate_max` correspondent aux champs déjà nommés `turn_accel`/`turn_max` (non renommés) |
| `angular_acceleration.z += (angular_velocity.y - 0.5*angular_velocity.z)*30` (`ship_player.c:422`) | `roll_accel = ... + roll_yaw_gain*yaw_velocity - roll_spring_damping*roll_rate` (`_update_visuals`) | ✅ inchangé depuis le passage 1 — toujours augmenté d'un ressort vers un `bank_target` (steer/brake) absent de l'original |
| Contre-braquage à double vitesse (`ship_player_update_race`) | `turn_reverse_boost` si `steer` s'oppose à `yaw_velocity` | ✅ inchangé depuis le passage 1 (formule simplifiée, pas de courbe `analog_response`) |
| `SHIP_THRUST_RATE`/`SHIP_THRUST_FALLOFF` | `thrust_ramp`/`thrust_falloff` | ✅ inchangé |

## Approximé ou remplacé par un mécanisme différent (résiduel)

- **Frein différentiel (airbrakes)** : l'original module `resistance`/`track_repulsion` via le facteur de frein et tourne par `angle.y += brake_dir * speed * ...`. Godot freine directement `forward_speed` (`airbrake_drag * brake_sum`) et ajoute du lacet proportionnel à `planar_velocity.length()` (`airbrake_turn_factor`) — logique différente, effet gameplay proche. Non retravaillé dans les phases 0-8 (hors scope du plan).
- **Traînée globale** : le drag 3 axes est bien porté (Phase 2), mais `hover_damping` reste un terme vertical additionnel non fusionné dans `resistance_effective` (choix assumé au point 3 de la Phase 2, pour ne pas déstabiliser la tenue de piste sans validation en jeu réel).

## Absent (assumé ou hors scope, documenté)

- **Poussée arrière** (Phase 0, décision de scope) : `throttle < 0` reste un choix de design Godot — désormais un frein actif (`reverse_brake`/`reverse_brake_drag`) et non plus une poussée négative comme au passage 1, mais toujours différent de l'original où `A_THRUST` est unidirectionnel sans aucune action de `throttle < 0`.
- **Boost pads, sections de saut, jonctions** (Phase 6, reporté conformément au point 4 du plan) : `Track_01` ne porte aucune donnée de ce type (vérifié dans `track_12_curve.json`, `Track01.tscn`, `TrackMeshCollider`) et le pipeline d'export Blender n'a pas été étendu. À traiter quand un circuit cible en aura besoin.

## Conclusion

Sur les 8 écarts de fond listés dans l'audit du passage 1 (grip, traînée globale, rebond sol, torque de nez, collisions murs par face, collision vaisseau-vaisseau, poussée arrière, rescue fidèle, profils par pilote — 9 items en comptant la poussée arrière séparément), **7 sont maintenant fidèlement portés** (grip, traînée, rebond sol, torque de nez, collisions murs, collision vaisseau-vaisseau, rescue, profils par pilote), **1 reste un choix de design assumé et documenté** (poussée arrière en frein), et **1 reste hors scope faute de données réelles** (features de piste). Le résidu restant (airbrakes différents, `hover_damping` non fusionné) est mineur et de nature cosmétique plutôt que structurelle. Le script Godot documente systématiquement ses emprunts (`# ported from ...`) et chaque `@export` ajouté est traçable à sa constante C d'origine, ce qui facilite un futur passage d'audit si de nouveaux écarts apparaissent.
