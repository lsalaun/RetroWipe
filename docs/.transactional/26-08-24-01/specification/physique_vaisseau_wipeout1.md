# Physique d'un vaisseau WipEout 1

Principes physiques du vaisseau dans le moteur original
([src/wipeout/ship_player.c](../../../../../src/wipeout/ship_player.c) et
[src/wipeout/ship.h](../../../../../src/wipeout/ship.h)), et état du portage
dans [wipeout_ship.gd](../../../src/scripts/wipeout_ship.gd) /
[docs/physique_vaisseau.md](../../physique_vaisseau.md).

## 1. Sustentation (hover) — loi d'aimant inverse, pas un ressort

Le vaisseau ne "flotte" pas sur un ressort linéaire : la répulsion suit une
**loi inverse de la hauteur** au-dessus de la piste :

$$\text{repulsion} = 4096 \times \left(\frac{\text{MAGNET} \times \text{FLOAT}}{\text{height}} - \text{MAGNET}\right)$$

- Très proche du sol → forte poussée vers le haut.
- Au-dessus de la hauteur cible → force **négative** (tire vers le bas), effet
  magnétique réel, pas juste "plus de ressort".
- En dessous de `height <= 0` → rebond dur : `velocity = reflect(velocity, normal) * 0.875`
  (restitution amortie).
- Entre 0 et 30 unités → petite poussée douce supplémentaire, avant même le
  calcul de `track_repulsion`.

## 2. Poussée (thrust) — rampe asymétrique

- Montée : `thrust_mag += input * SHIP_THRUST_RATE`
- Chute (relâché) : `thrust_mag -= SHIP_THRUST_FALLOFF` avec **FALLOFF = RATE / 2**.

Le vaisseau perd sa poussée deux fois moins vite qu'il ne l'accumule → inertie
caractéristique quand on relâche l'accélérateur.

## 3. Virage (yaw) — flick asymétrique + auto-retour

- Braquer **dans le sens du virage actuel** → accélération angulaire normale,
  plafonnée par `turn_rate_max` (courbe exponentielle en `analog_response`
  pour l'input analogique).
- Braquer **en contre-sens** (contre-braquage) → accélération **doublée**
  (`turn_rate * 2`), ce qui permet les flick-turns rapides typiques de la
  série.
- Sans input → l'accélération angulaire ramène `angular_velocity.y` vers 0 au
  taux `turn_rate` (pas un simple damping exponentiel).
- Le "steering" au frein différentiel (`brake_left - brake_right`) ajoute
  directement un delta à `angle.y`, proportionnel à la vitesse — c'est un vrai
  survirage au frein, pas juste du yaw.

## 4. Roulis (roll) — masse-ressort piloté par le lacet

```
angular_acceleration.z += (angular_velocity.y - 0.5 * angular_velocity.z) * 30
angle.z -= angle.z * 0.125 * 30 * dt   // auto-nivellement
```

Le roulis en virage est un vrai système masse-ressort-amorti asservi à la
vitesse de lacet, avec retour automatique à plat — pas un simple lerp
cosmétique.

## 5. Tangage (pitch) — nez qui s'enfonce

Si le nez du vaisseau (`nose_pos` à 128 unités devant) est plus bas que 600
unités au-dessus de la piste, un couple de tangage le repousse en fonction de
la différence `height - nose_height`. Sinon, un couple constant vers le bas
simule la "chute" naturelle du nez.

## 6. Résistance/traînée — dépend du sol vs air, et du freinage

- Au sol : `resistance = ship.resistance * (MAX_RESISTANCE - brake*0.125) * k`
- En vol : `resistance = ship.resistance * (MAX_RESISTANCE - brake*0.125) * k`
  mais avec un dénominateur de "skid" différent
  (`MIN_RESISTANCE + brake*4` au lieu de `skid + brake*0.25`) → beaucoup moins
  de grip en l'air, glisse plus.
- La composante `(forward_velocity - velocity) / (skid + brake*0.25)` réaligne
  la vitesse vers l'axe du vaisseau — c'est ce qui donne le "grip" au sol vs
  le côté "dérive" en l'air.

## 7. Gravité différente sol/air

`SHIP_ON_TRACK_GRAVITY` (30000) est bien plus faible que
`SHIP_FLYING_GRAVITY` (80000) — en vol, le vaisseau tombe beaucoup plus vite
qu'au sol (où le magnet de piste compense la gravité normale).

## Ce qui est déjà porté dans `wipeout_ship.gd`

D'après [docs/physique_vaisseau.md](../../physique_vaisseau.md), l'ensemble
des points 1 à 7 ci-dessus sont désormais portés avec des paramètres
`@export` correspondants dans
[wipeout_ship.gd](../../../src/scripts/wipeout_ship.gd) : sustentation en loi
d'aimant inverse (1), ratio de poussée 2:1 (2), flick asymétrique au virage +
survirage au frein différentiel (3), roulis masse-ressort (4), tangage
nez-qui-plonge (5), grip/résistance différenciés sol/air (6) et gravité
différente sol/air (7).

## Détails d'implémentation

- **Gravité sol/air** : portée via `ground_gravity_scale` (0.375 =
  `SHIP_ON_TRACK_GRAVITY / SHIP_FLYING_GRAVITY`), appliquée à `gravity`
  uniquement au sol, dans `_apply_hover_forces()`.
- **Résistance/grip différenciés sol/air** : `_apply_drive_forces()` utilise
  le même diviseur de traînée (`max_resistance`) au sol et en vol comme
  l'original, et différencie uniquement le diviseur de grip
  (`skid + brake*0.25` au sol vs `min_resistance + brake*4` en vol), en
  remplacement de l'ancien `airborne_lateral_friction` (retiré de
  `WipeoutShip`, `ShipHandlingProfile` et des `.tres`).
- **Virage au frein différentiel** : `brake_yaw_rate` applique une
  contribution transitoire au cap dans `_update_orientation()`, recalculée
  chaque frame et non accumulée dans `yaw_velocity` — relâcher le frein arrête
  l'effet immédiatement, comme `angle.y += brake_dir * speed * k` dans
  l'original.
- **Rescue droid / `SECTION_JUMP`** : toujours hors périmètre. L'architecture
  Godot n'a pas de structure de sections/faces de piste (seulement une
  `Curve3D` pour `center_line`), donc `_rescue_to_track()` reste une
  approximation (retour sur la ligne centrale) sans détection de saut de
  piste ni redirection vers une section d'atterrissage. Porter ce
  comportement fidèlement nécessiterait de modéliser les sections de piste,
  ce qui dépasse le cadre d'un ajustement ciblé de la physique.

Détails et formules dans [docs/physique_vaisseau.md](../../../physique_vaisseau.md#5-gravité-différente-solair).
