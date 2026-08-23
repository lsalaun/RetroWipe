# Plan d'implémentation — Convergence physique du vaisseau

Basé sur l'audit `../audit/ship_physics_fidelity_audit_01.md`. Objectif : faire converger `godot/src/scripts/wipeout_ship.gd` vers le modèle physique original (`src/wipeout/ship_player.c`, `ship.c`, `ship.h`) sans casser le gameplay Godot existant (raycasts de hover, `CharacterBody3D`, `move_and_slide`).

Chaque phase est indépendante et testable isolément. Ordre recommandé : 0 → 6 (7, 8, 9 optionnelles / plus gros chantiers).

## Phase 0 — Décisions de scope

À trancher avant de coder, car elles changent la portée des phases suivantes :

- ✅ **Poussée arrière** (`throttle < 0`) : implémenté — `thrust_mag` est clampé à `>= 0` (`maxf(thrust_mag, 0.0)`) et `throttle < 0` ramp un facteur `reverse_brake` (via `airbrake_rate`) qui applique une décélération `reverse_brake_drag` sur `forward` dans `_apply_drive_forces`, au lieu d'une poussée négative. Nouvel `@export var reverse_brake_drag` ajouté sur `WipeoutShip` et `ShipHandlingProfile` (+ `apply_to`). `reverse_brake` réinitialisé dans `_reset_to_spawn`.
- **Attributs par pilote/équipe** (Phase 8) : nécessaire seulement si le jeu prévoit plusieurs vaisseaux avec des caractéristiques différentes. Si un seul vaisseau jouable est prévu à court terme, reporter cette phase.
- **Features de piste** (boost pads, jump sections, junctions — Phase 6) : nécessitent un pipeline d'export de métadonnées de piste (Blender → Godot) qui n'existe pas encore. À traiter comme un chantier séparé si le circuit cible en a besoin.

## Phase 1 — Grip / dérapage (`skid`) ✅ implémenté

`lateral_friction` a été retiré (remplacé par `skid`) sur `WipeoutShip` et `ShipHandlingProfile` (+ `arcade_profile.tres`, `default_profile.tres`, `stable_profile.tres`). Dans `_apply_drive_forces`, au sol le bloc de friction latérale est remplacé par le blend `(forward_velocity - velocity) / grip_denominator`; en vol, `airborne_lateral_friction` est conservé tel quel (branche `else`) comme prévu au point 3.

**Écart d'origine** : Godot utilisait une friction latérale simple (`velocity -= right * lateral_speed * lateral_friction * delta`) au lieu du terme original qui ramène `velocity` vers `forward_velocity` :

```
acceleration += (forward_velocity - velocity) / (skid + brake * 0.25)
```

**Implémentation** :
1. Ajouter `@export var skid: float = <valeur calibrée>` sur `WipeoutShip`.
2. Dans `_apply_drive_forces`, remplacer le bloc friction latérale par :
   ```gdscript
   var forward_velocity := forward * velocity.length()
   var grip_denominator := maxf(skid + (brake_left + brake_right) * 0.25, 0.001)
   velocity += (forward_velocity - velocity) / grip_denominator * delta
   ```
3. Conserver `airborne_lateral_friction` comme facteur multiplicatif appliqué seulement si `not grounded` (l'original utilise un dénominateur différent en vol via `SHIP_MIN_RESISTANCE + brake*4`, cf. Phase 2).
4. Retirer le calcul de `lateral_speed`/`right` s'il devient inutilisé, sauf s'il sert encore pour `_planar_right` ailleurs.

**Validation** : sur ligne droite, un `steer` bref doit faire déraper l'arrière puis se réaligner progressivement sur l'axe du vaisseau (pas une correction instantanée comme avec `lateral_friction` élevé).

## Phase 2 — Traînée globale (drag 3 axes) + résistance sol/air ✅ implémenté

`planar_drag` a été retiré (remplacé par `resistance` + `max_resistance`/`min_resistance`/`resistance_brake_scale`/`resistance_k`) sur `WipeoutShip` et `ShipHandlingProfile` (+ les 3 `.tres`). Dans `_apply_drive_forces`, l'ordre a été rapproché de l'original (friction/skid → poussée → drag) : le calcul du grip (Phase 1) précède désormais l'ajout de la poussée, suivi d'un drag global appliqué sur `velocity` en 3D (`velocity -= velocity * (delta / resistance_effective)`), avec `resistance_effective` plus grand au sol (moins de drag) et plus petit en vol (plus de drag), tous deux atténués par `brake_sum`. `hover_damping` est conservé tel quel dans `_apply_hover_forces` (option de repli du point 3, non remplacé) puisque ce drag global s'applique déjà sur l'axe vertical.

**Écart d'origine** : l'original applique `acceleration -= velocity / resistance` sur les 3 axes, avec `resistance` dépendant du freinage et différente au sol (`SHIP_MAX_RESISTANCE`) vs en vol (`SHIP_MIN_RESISTANCE`). Godot séparait drag planaire (`planar_drag`) et amortissement vertical (`hover_damping`).

**Implémentation** :
1. Ajouter `@export var resistance: float` et utiliser les constantes de référence :
   - Sol : `resistance_effective = resistance * (max_resistance - brake_sum * 0.125 * scale) * k`
   - Vol : dénominateur `min_resistance + brake_sum * k`
2. Fusionner Phase 1 et Phase 2 dans un seul recalcul de `acceleration` en `_apply_drive_forces` / nouvelle fonction `_compute_acceleration(...)` pour rester proche de la structure originale (accumulation additive : friction/skid, puis force/mass, puis drag), plutôt que des corrections `velocity +=` dispersées comme actuellement.
3. Remplacer `hover_damping` (vertical uniquement) par le drag global une fois validé que la tenue de piste ne devient pas instable ; sinon garder `hover_damping` comme terme additionnel réduit.

**Validation** : mesurer le temps de stabilisation de la vitesse à poussée constante (doit converger vers une vitesse de palier, pas osciller ni diverger).

## Phase 3 — Contact sol : rebond dur + alignement du nez

**Écarts** :
- Pas de rebond dur quand `height <= 0` (réflexion de vélocité, atténuation 0.875).
- Pas de torque de tangage basé sur `nose_height` (`ship_player.c:370-377`) — l'assiette actuelle vient d'un `slerp` générique vers la normale du hover.

**Implémentation** :
1. Dans `_sample_hover`, exposer une hauteur "avant" séparée en ajoutant un 5ᵉ raycast au nez (ou en dérivant la hauteur nez depuis les deux rayons avant existants) pour approx `nose_height`.
2. Dans `_apply_hover_forces`, ajouter :
   ```gdscript
   if hover.height <= 0.0:
       velocity = velocity.bounce(up) * 0.875
       velocity -= up * (floor_push_speed * delta)
   elif hover.height < bounce_margin:
       velocity += up * (floor_push_speed * delta)
   ```
   Réutiliser des constantes existantes (`hover_force`) plutôt que d'introduire trop de nouveaux `@export`.
3. Ajouter un terme d'accélération angulaire de tangage basé sur la différence hauteur nez/hauteur coque, appliqué avant l'intégration de `_update_orientation` (actuellement piloté seulement par `pitch_input`).

**Validation** : passage sur une bosse ou un creux doit incliner visiblement le nez avant que le `slerp` générique ne prenne le relais, et un contact vertical dur (chute depuis une rampe) doit produire un vrai rebond au lieu d'un arrêt mou.

## Phase 4 — Collisions murales par face (nez / aile)

**Écart** : `_handle_wall_collisions` fait un rebond générique (`velocity.bounce(normal) * wall_bounce_damping`) avec un `wall_turn_kick` fixe, sans distinguer un choc de nez d'un choc d'aile, ni scaler selon la vitesse/l'angle d'impact.

**Implémentation** :
1. Déterminer le point de contact réel (`collision.get_position()`) par rapport au centre du vaisseau et au `forward` pour classer la collision : nez (proche de l'axe avant) vs aile (décalée latéralement) — seuil sur la projection latérale du point de contact.
2. Porter les formules originales :
   - `velocity = vec3_reflect(velocity, normal, 2)` puis `velocity *= 0.5` puis `velocity += normal * push_constant` (remplace le simple `bounce * wall_bounce_damping`).
   - Magnitude angulaire :
     - Aile : `magnitude = |angle(collision_vector, forward)| * speed * k`, appliquée à un axe de roulis (`roll_rate` ou `angular` équivalent) selon le côté touché.
     - Nez : `magnitude = (speed * k1 + k2)`, appliquée au lacet (`yaw_velocity`).
3. Garder un anti-spam d'impact (équivalent `last_impact_time`) si un SFX d'impact est ajouté plus tard.

**Validation** : un choc frontal doit induire une rotation en lacet (yaw kick) sans forte perte de vitesse latérale ; un choc d'aile doit induire un roulis marqué et amortir la vitesse davantage.

## Phase 5 — Collision vaisseau-vaisseau

**Écart** : absente. L'original fait une collision inélastique par conservation de quantité de mouvement pondérée par la masse (`ship_collide_with_ship` dans `ship.c`).

**Implémentation** :
1. Créer un gestionnaire au niveau race/scene (pas dans `wipeout_ship.gd` individuellement, pour éviter double-traitement A↔B) : `ShipCollisionManager` (ou fonction statique) itérant sur toutes les paires de vaisseaux actifs chaque frame physique.
2. Détection : distance rapide (`> seuil` → skip) puis test de recouvrement des formes de collision (`Area3D`/`CollisionShape3D` dédiée par vaisseau, distincte du corps de hover).
3. Résolution, portée depuis `ship_collide_with_ship` :
   ```
   vc = (v_self*m_self + v_other*m_other) / (m_self+m_other)
   v_self  += (vc - v_self) * 0.5
   v_other += (vc - v_other) * 0.5
   separation = position_self - position_other
   v_self  += separation * push_k
   v_other -= separation * push_k
   ```
4. Exposer `mass` en `@export` sur `WipeoutShip` (déjà nécessaire pour Phase 2 force/mass si pas encore fait).

**Validation** : deux vaisseaux se percutant de face doivent échanger de la vitesse proportionnellement à leur masse respective et se repousser sans s'interpénétrer ni se figer.

## Phase 6 — Parité des features de piste (boost, jump, junction)

**Écart** : aucune donnée de face de piste (boost pads, sections de saut, jonctions) n'est portée ; `TrackMeshCollider` ne génère que des colliders génériques.

**Implémentation** (chantier plus large, pipeline requis) :
1. Étendre l'export de piste (Blender/JSON, cf. mémoire sur `export_track_curve.py`) pour taguer les faces spéciales (boost/jump/junction) via des noms d'objets ou des groupes de vertex.
2. Représenter ces zones comme des `Area3D` triggers dans la scène de piste plutôt que de la géométrie de collision (plus simple à interroger que des flags de face comme en C).
3. Dans `wipeout_ship.gd`, ajouter des signaux/handlers : `_on_boost_area_entered` (ajoute une impulsion `velocity += track_direction * boost_accel * delta` tant que dans la zone), et une logique de détection de vol au-dessus d'une section `jump` réutilisant `airborne_time`/`_sample_hover`.
4. Reporter tant que le circuit cible ne contient pas ces éléments.

## Phase 7 — Système de secours (rescue) fidèle

**Écart** : Godot utilise un timeout générique (`airborne_time > rescue_delay`) + seuil `y < -25`. L'original calcule la distance à la ligne centrale de la piste (projection sur le segment section→section suivante) et re-largue le vaisseau à la dernière section valide ou à l'atterrissage d'un saut.

**Implémentation** :
1. Nécessite une notion de "section de piste courante" côté Godot — si absente, dériver une approximation via le point le plus proche sur une `Curve3D` centrale de piste (déjà générée pour d'autres besoins, cf. `track_center_line.gd` en mémoire de session/projet).
2. Remplacer `_reset_to_spawn` par une téléportation vers le point de piste valide le plus proche en arrière, avec une petite tolérance de hauteur (`rescue_height`), au lieu du reset complet à `spawn_transform`.
3. Garder le fallback `y < -25.0 → reset spawn` comme filet de sécurité ultime.

## Phase 8 — Profils d'attributs par pilote/équipe

**Écart** : un seul jeu de `@export` sur le nœud, pas de système `def.teams[team].attributes[class]` (mass, thrust_max, skid, turn_rate, turn_rate_max, resistance).

**Implémentation** :
1. Créer une `Resource` `ShipHandlingProfile` (étendre le `handling: Resource` déjà présent) avec les champs : `mass`, `thrust_max`, `skid`, `turn_rate`, `turn_rate_max`, `resistance`.
2. `apply_to(ship)` déjà appelé dans `_ready()` — l'étendre pour écrire ces nouveaux champs sur le vaisseau au lieu de dupliquer les constantes par défaut.
3. Un `.tres` par pilote/équipe/classe, chargé selon la sélection du joueur/IA.

## Phase 9 — Validation & non-régression

1. Ajouter une scène de test isolée (piste courte + un vaisseau) pour valider chaque phase indépendamment avant intégration.
2. Documenter, pour chaque `@export` modifié ou ajouté, sa correspondance avec la constante C d'origine (comme déjà fait pour certains champs) — garde la traçabilité pour le prochain audit.
3. Une fois les phases 1 à 5 terminées, refaire un passage d'audit (même méthode que `ship_physics_fidelity_audit_01.md`) pour mesurer la réduction des écarts.

## Ordre de priorité suggéré

1. Phase 1 (grip/skid) — impact gameplay le plus direct et le plus visible.
2. Phase 2 (drag global) — dépend de/complète Phase 1.
3. Phase 4 (collisions murales par face) — bugs de gameplay actuels probables (rebonds génériques).
4. Phase 3 (contact sol/rebond/nez) — stabilité de la conduite.
5. Phase 5 (collision vaisseau-vaisseau) — nécessaire seulement en multi-vaisseaux actifs simultanément.
6. Phases 6, 7, 8 — chantiers plus larges, à planifier selon les besoins du circuit/mode de jeu ciblé.
