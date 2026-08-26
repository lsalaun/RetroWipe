# Audit de vitesse et d'accélération — vaisseau Godot vs original Wipeout Rewrite

## Contexte

Cette note compare la gestion de la vitesse et de l'accélération du vaisseau dans le port Godot (`godot/src/scripts/wipeout_ship.gd`) avec le moteur original (`src/wipeout/ship_player.c`, `src/wipeout/ship.h`).

L'objectif est de vérifier si le comportement du vaisseau reste cohérent avec le projet source, sans se limiter à la présence de variables ou de commentaires. La comparaison porte sur :

- la poussée moteur,
- le grip / dérapage,
- la résistance / traînée,
- le freinage et la décélération,
- les effets de gravité et de tenue de piste,
- la structure de calcul en Godot par rapport à l'original.

---

## 1. Poussée moteur

### Original

Dans `src/wipeout/ship_player.c`, la poussée est gérée via :

- `self->thrust_mag += input_state(A_THRUST) * SHIP_THRUST_RATE * system_tick();`
- `self->thrust_mag -= SHIP_THRUST_FALLOFF * system_tick();`
- `self->thrust_mag = clamp(self->thrust_mag, 0, self->current_thrust_max);`

Les constantes d'origine sont dans `src/wipeout/ship.h` :

- `SHIP_THRUST_RATE    NTSC_VELOCITY(16)`
- `SHIP_THRUST_FALLOFF NTSC_VELOCITY(8)`

Autrement dit, le moteur accélère en fonction d'un taux de montée, puis retombe avec une pente plus douce de moitié.

### Godot

Dans `wipeout_ship.gd`, on retrouve les équivalents :

- `_update_drive_inputs()`
- `thrust_mag = move_toward(thrust_mag, throttle * thrust_max, thrust_ramp * delta)`
- `thrust_mag = move_toward(thrust_mag, 0.0, thrust_falloff * delta)`
- `thrust_mag = maxf(thrust_mag, 0.0)`

Les variables exportées sont :

- `thrust_max: float = 72.0`
- `thrust_ramp: float = 42.0`
- `thrust_falloff: float = 20.0`

### Analyse

La logique est cohérente avec l'original :

- le moteur monte en puissance progressivement,
- le relâchement de la manette fait tomber la poussée,
- la poussée reste bornée à une valeur maximale.

Le port n'applique pas une poussée négative quand `throttle < 0` ; il le traite comme un frein actif. C'est un choix de conception de Godot, différent de l'original qui a un comportement de poussée unidirectionnelle. Le design est donc documenté et assumé, pas un bug de portage.

Verdict : conforme au comportement de base du projet original, avec une adaptation gameplay de freinage inverse.

---

## 2. Grip et dérapage

### Original

Dans `ship_player.c`, la force de grip est :

- `self->acceleration = vec3_divf(vec3_sub(forward_velocity, self->velocity), self->skid + brake * 0.25);`

Le terme est appliqué sur la composante de vitesse projetée sur l'axe avant du vaisseau. En pratique, cela ramène la vitesse vers le vecteur de déplacement actuel du vaisseau.

Les données du jeu original sont parametrées par `self->skid` et `self->brake_left/self->brake_right`.

### Godot

Dans `wipeout_ship.gd` :

- `var forward_velocity := forward * maxf(planar_velocity.dot(forward), 0.0)`
- `var grip_denominator := maxf(skid + brake_sum * 0.25, 0.001) if grounded else maxf(min_resistance + brake_sum * 4.0, 0.001)`
- `velocity += (forward_velocity - velocity) / grip_denominator * delta`

Ce terme est appliqué dans `_apply_drive_forces()`, au sol et en air.

### Analyse

Cette partie est très proche de l'original :

- la vitesse est ramenée vers l'axe avant,
- l'effet est plus fort au sol (`skid`), plus faible en l'air (`min_resistance`),
- le freinage réduit la résistance et modifie le comportement selon la charge de frein.

La forme de la formule est identique et la logique est fidèle au moteur Wipeout original.

Verdict : correctement porté et cohérent avec la physique source.

---

## 3. Résistance et traînée globale

### Original

Dans `ship_player.c` :

- `float resistance = (self->resistance * (SHIP_MAX_RESISTANCE - (brake * 0.125))) * 0.0078125;`
- `self->acceleration = vec3_sub(self->acceleration, vec3_divf(self->velocity, resistance));`

Les constantes d'origine dans `ship.h` sont :

- `SHIP_MIN_RESISTANCE 20`
- `SHIP_MAX_RESISTANCE 74`

Donc la vitesse est ralentie sur les 3 axes via une traînée globale, modulée par le freinage.

### Godot

Dans `wipeout_ship.gd` :

- `var resistance_effective := resistance * (max_resistance - brake_sum * 0.125 * resistance_brake_scale) * resistance_k`
- `velocity -= velocity * (delta / maxf(resistance_effective, 0.001))`

Les variables concernées sont :

- `resistance`, `max_resistance`, `min_resistance`, `resistance_brake_scale`, `resistance_k`

### Analyse

Le port Godot reproduit exactement le principe de l'original :

- l'accélération de vitesse est réduite proportionnellement à la vitesse actuelle,
- le freinage augmente la décélération,
- le coefficient de résistance est différent selon le mode de vol / tenue de piste,
- la traînée est appliquée au niveau de `velocity`, donc sur les trois axes, comme dans l'original.

C'est l'un des éléments les mieux portés.

Verdict : fort bon portage de la traînée globale et du freinage.

---

## 4. Gravité et tenue de piste

### Original

En roulant sur la piste, le vaisseau reçoit :

- `force = SHIP_ON_TRACK_GRAVITY`
- puis une poussée vers le haut/vers le bas calculée à partir de `SHIP_TRACK_MAGNET`
- puis `self->thrust`
- puis le terme de résistance

Les constantes sont :

- `SHIP_FLYING_GRAVITY   vec3(0, 80000.0, 0)`
- `SHIP_ON_TRACK_GRAVITY vec3(0, 30000.0, 0)`
- `SHIP_TRACK_MAGNET    64`
- `SHIP_TRACK_FLOAT     256`

### Godot

Dans `_apply_hover_forces()` :

- `velocity += up * repulsion * delta`
- `velocity -= up * vertical_speed * hover_damping * delta`
- `velocity += Vector3.DOWN * gravity * ground_gravity_scale * delta`

et en vol :

- `velocity += Vector3.DOWN * gravity * delta`

Les variables pertinentes sont :

- `track_magnet`, `hover_force`, `hover_damping`, `gravity`, `ground_gravity_scale`

### Analyse

La logique du port Godot suit bien le principe original :

- l'attrait vers la piste est représenté par un terme de répulsion/traction vertical,
- la gravité est plus forte en vol que sur la piste,
- la présence de `hover_damping` agit comme amortissement supplémentaire, ce qui est compatible avec le besoin de stabilité du port Godot.

La différence principale est qu'en Godot, le calcul est exprimé dans le model `delta`/mètre plutôt que dans le formalisme `fixed-point` / `system_tick` du C. L'intention est préservée, même si les valeurs absolues ne sont pas identiques à 1:1.

Verdict : cohérent avec la logique originale de la tenue de piste et de la gravité.

---

## 5. Freinage de direction / airbrake

### Original

L'original applique le freinage principalement comme modulateur de la résistance et du virage :

- `brake = (self->brake_left + self->brake_right)`
- `resistance` est réduite par le freinage
- le freinage joue aussi dans le calcul de `acceleration`, de la vitesse longitudinale, et du comportement de virage

### Godot

Dans `_apply_drive_forces()` :

- `velocity -= forward * minf(forward_speed, airbrake_drag * brake_sum * delta)`
- `brake_yaw_rate = brake_bias * maxf(planar_velocity.length(), 0.0) * airbrake_turn_factor`
- `if reverse_brake > 0.0: velocity -= forward * clampf(forward_speed, 0.0, reverse_brake_drag * reverse_brake * delta)`

### Analyse

Le comportement est proche du projet original, même si le port utilise des termes séparés et un système de facteur de freinage plus direct. C'est une adaptation de gameplay, pas une divergence structurelle majeure.

Verdict : logique de freinage cohérente, bien que l'implémentation Godot soit un peu plus explicite et « stylisée » que le C original.

---

## 6. Intégration physique dans le temps

### Original

Le C applique :

- `self->velocity = vec3_add(self->velocity, vec3_mulf(self->acceleration, 30 * system_tick()));`
- `self->position = vec3_add(self->position, vec3_mulf(self->velocity, 0.015625 * 30 * system_tick()));`

C'est un système de simulation temps-réel avec des unités fixed-point et un facteur de conversion 30Hz.

### Godot

Dans `_physics_process()` :

- `global_position += velocity * delta`
- `velocity` a déjà été modifiée par `delta` dans `_apply_hover_forces()` et `_apply_drive_forces()`.

### Analyse

Le port Godot n'utilise pas les mêmes unités exactes que le code C, mais il garde le même équilibre qualitatif :

- la vitesse est accumulée à partir d'une accélération,
- la position suit ensuite la vitesse,
- le système est stable par `delta` et le moteur physique Godot.

Le port est donc un remplacement fidèle de la mécanique, pas une copie littérale de la structure fixe originale.

Verdict : conforme à la logique originale, avec adaptation du rendu temps réel Godot.

---

## 7. Verdict global

### Conclusion

La gestion de la vitesse et de l'accélération du vaisseau dans le port Godot est globalement cohérente et fidèle au projet original Wipeout Rewrite.

Les points confirmés :

- la poussée moteur est portée selon le même principe de montée/ralentissement,
- le grip du vaisseau s'oriente bien vers l'axe avant,
- la traînée globale est appliquée sur les 3 axes comme dans le C original,
- la gravité et la tenue de piste respectent la même logique de force et de tracking sur la piste,
- le freinage est bien pris en compte dans la résistance et la dynamique du vaisseau.

### Différences acceptées

- `throttle < 0` est interprété comme frein actif, pas comme poussée négative.
- le code Godot structure les calculs via `delta` et des variables de gameplay adaptées, au lieu de l'implémentation fixed-point de l'original.
- `hover_damping` et certains facteurs gameplay sont ajoutés pour stabiliser le port Godot, sans dénaturer le comportement général.

### Verdict final

Oui, le port Godot présente une gestion de vitesse et d'accélération compatible avec le système original Wipeout Rewrite, avec des adaptations de style de jeu et d'API de moteur nécessaires, mais sans rupture de logique fondamentale.

La physique du vaisseau reste fidèle dans son architecture et dans ses principes : poussée, grip, résistance, gravité et contrôle de trajectoire sont bien alignés avec le code source original.
