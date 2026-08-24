# Physique du vaisseau — portage depuis le moteur C original

Ce document résume l'analyse de la physique du vaisseau dans le jeu original
([src/wipeout/ship_player.c](../../src/wipeout/ship_player.c) et
[src/wipeout/ship.h](../../src/wipeout/ship.h)) et son portage dans
l'implémentation Godot ([godot/src/scripts/wipeout_ship.gd](../src/scripts/wipeout_ship.gd)).

## Contexte

L'architecture originale (PSX) simule le vaisseau par rapport à des **sections
et faces de piste fixes** (`track_face_t`, `section_t`), avec des collisions et
un alignement au sol résolus directement contre cette géométrie de piste.

L'implémentation Godot utilise une architecture différente : un
`CharacterBody3D` avec 4 `RayCast3D` pour le survol (hover) et
`move_and_slide()` pour les collisions génériques. Un portage 1:1 exact des
formules à virgule fixe de l'original n'est donc pas possible sans réécrire
tout le système de piste. Le travail effectué porte les **comportements
physiques distinctifs** qui définissent la sensation de conduite WipEout,
adaptés à l'architecture raycast/CharacterBody3D existante.

## Comportements portés

### 1. Virage en "flick" asymétrique (contre-braquage rapide)

Dans l'original, braquer dans la direction **opposée** à la rotation
angulaire actuelle applique une accélération angulaire **double** :

```c
if (input_state(A_LEFT)) {
    if (self->angular_velocity.y < 0) {
        self->angular_acceleration.y += self->turn_rate * 2; // contre-braquage rapide
    } else {
        // rampe normale vers turn_rate_max
    }
}
```

Porté dans `_apply_drive_forces()` via `turn_reverse_boost` : quand `steer` et
`yaw_velocity` ont des signes opposés, l'accélération de lacet est multipliée
par `turn_reverse_boost` (2.0 par défaut) au lieu du taux normal.

### 2. Loi d'aimantation de piste ("track magnet")

L'original utilise une répulsion en **loi inverse de la hauteur**, pas un
ressort de compression linéaire :

```c
float track_repulsion = 4096 * (SHIP_TRACK_MAGNET * SHIP_TRACK_FLOAT / height - SHIP_TRACK_MAGNET);
```

Cette loi pousse fort près du sol et **tire légèrement vers le bas** quand le
vaisseau est au-dessus de la hauteur cible (un vrai effet d'aimant, pas
seulement un ressort à une seule direction).

Porté dans `_apply_hover_forces()` :

```gdscript
var repulsion := clampf(track_magnet * (hover_height / height - 1.0) * hover_force, -hover_force * 2.0, hover_force * 6.0)
```

### 3. Roulis en ressort amorti (banking dans les virages)

L'original modélise le roulis (`angle.z`) comme un vrai système masse-ressort
piloté par la vitesse de lacet, avec un retour automatique à zéro :

```c
self->angular_acceleration.z += (self->angular_velocity.y - 0.5 * self->angular_velocity.z) * 30;
// ...
self->angle.z -= self->angle.z * 0.125 * 30 * system_tick(); // auto-nivellement
```

Porté dans `_update_visuals()` en remplaçant l'ancien lerp cosmétique par un
système masse-ressort équivalent, piloté par `yaw_velocity` avec les gains
`roll_yaw_gain` et `roll_spring_damping`. Ce portage a aussi corrigé un bug de
signe préexistant (`yaw_velocity * -0.18`) qui faisait pencher le maillage du
mauvais côté par rapport à la direction réelle du virage.

### 4. Ratio rampe/chute de poussée

L'original ralentit la poussée deux fois moins vite qu'il ne l'augmente :

```c
#define SHIP_THRUST_RATE    NTSC_VELOCITY(16)
#define SHIP_THRUST_FALLOFF NTSC_VELOCITY(8) // moitié du taux de rampe
```

`thrust_falloff` a été ajusté de 28 à 20 pour respecter approximativement ce
ratio 2:1 par rapport à `thrust_ramp` (42).

### 5. Gravité différente sol/air

L'original applique une gravité bien plus forte en vol qu'au sol (où le
magnet de piste compense l'essentiel de la chute) :

```c
#define SHIP_FLYING_GRAVITY   vec3(0, 80000.0, 0)
#define SHIP_ON_TRACK_GRAVITY vec3(0, 30000.0, 0)
```

Porté dans `_apply_hover_forces()` via `ground_gravity_scale` (0.375 =
30000/80000 par défaut), appliqué à `gravity` uniquement au sol ; en vol,
`gravity` s'applique à pleine valeur.

### 6. Grip et résistance différenciés sol/air (mêmes constantes que l'original)

L'original réutilise **la même formule de résistance/traînée** au sol et en
vol (basée sur `SHIP_MAX_RESISTANCE`) ; ce qui diffère entre sol et air, c'est
le diviseur du terme qui ramène la vitesse vers l'axe avant du vaisseau
(le "grip") :

```c
// Sol : self->skid + brake * 0.25
self->acceleration = vec3_divf(vec3_sub(forward_velocity, self->velocity), self->skid + brake * 0.25);
// Air : SHIP_MIN_RESISTANCE + brake * 4 (beaucoup plus lâche)
self->acceleration = vec3_divf(vec3_sub(forward_velocity, self->velocity), SHIP_MIN_RESISTANCE + brake * 4);
// Traînée (même formule sol ET air) :
float resistance = (self->resistance * (SHIP_MAX_RESISTANCE - (brake * 0.125))) * 0.0078125;
self->acceleration = vec3_sub(self->acceleration, vec3_divf(self->velocity, resistance));
```

Porté dans `_apply_drive_forces()` : le terme de grip utilise désormais
`skid + brake_sum * 0.25` au sol et `min_resistance + brake_sum * 4.0` en
vol (au lieu d'un simple facteur de friction latérale `airborne_lateral_friction`,
qui a été retiré) ; le terme de traînée `resistance_effective` utilise
`max_resistance` de façon identique au sol et en vol, comme dans l'original.

### 7. Virage au frein différentiel — contribution transitoire, pas d'inertie

L'original ajoute directement au cap (`angle.y`) une contribution
proportionnelle à la vitesse et au différentiel de frein, recalculée chaque
image plutôt qu'accumulée comme une vitesse angulaire persistante :

```c
float brake_dir = (self->brake_left - self->brake_right) * (0.125 / 4096.0);
self->angle.y += brake_dir * self->speed * 0.000030517578125 * M_PI * 2 * 30 * system_tick();
```

Porté via `brake_yaw_rate`, calculé dans `_apply_drive_forces()` et appliqué
dans `_update_orientation()` en plus de `yaw_velocity`, mais sans jamais être
intégré dans `yaw_velocity` lui-même : relâcher le frein arrête l'effet
immédiatement, sans que `turn_damping` ait besoin de le dissiper.

## Paramètres exposés (`@export`)

| Paramètre | Rôle | Origine C |
|---|---|---|
| `turn_reverse_boost` | Multiplicateur d'accélération en contre-braquage | `turn_rate * 2` |
| `track_magnet` | Force de l'aimantation de piste (loi inverse) | `SHIP_TRACK_MAGNET` |
| `roll_yaw_gain` | Gain de banking automatique en fonction du lacet | coefficient de `angular_velocity.y` dans `angular_acceleration.z` |
| `roll_spring_damping` | Amortissement du ressort de roulis | coefficient `0.5` + auto-nivellement de `angle.z` |
| `thrust_falloff` | Taux de chute de la poussée | `SHIP_THRUST_FALLOFF` |
| `ground_gravity_scale` | Ratio de gravité au sol par rapport à la gravité aérienne | `SHIP_ON_TRACK_GRAVITY / SHIP_FLYING_GRAVITY` |
| `min_resistance` | Diviseur de grip en vol (plus grand = grip plus lâche) | `SHIP_MIN_RESISTANCE` |
| `max_resistance` | Base du terme de traînée, identique sol/air | `SHIP_MAX_RESISTANCE` |

Ces valeurs restent ajustables directement depuis l'inspecteur Godot pour
affiner la sensation de conduite sans toucher au code.

## Comportements non portés (hors périmètre)

- Résolution de collision avec la piste basée sur les faces/sections
  (`ship_collide_with_track`, `ship_resolve_nose_collision`,
  `ship_resolve_wing_collision`) : remplacée par `move_and_slide()` +
  raycasts, architecture fondamentalement différente.
- Logique de sauvetage (rescue droid) suivant les sections de piste et
  cas particulier `SECTION_JUMP` : l'implémentation Godot n'a pas de
  structure de sections/faces de piste (`center_line` est une simple
  `Curve3D`), donc `_rescue_to_track()` ne fait qu'une approximation
  (retour sur la ligne centrale, `rescue_look_back` en arrière) sans détecter
  les sauts de piste ni rediriger vers une section d'atterrissage. Porter ce
  comportement fidèlement demanderait de modéliser les sections de piste,
  hors périmètre de l'architecture raycast/CharacterBody3D actuelle.
- Effets de armes/tourbillons liés au gameplay de course (boost, ebolt, etc.).
