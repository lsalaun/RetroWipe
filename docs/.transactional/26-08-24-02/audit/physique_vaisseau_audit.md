# Audit — pistes d'amélioration de la physique du vaisseau

Suite à la vérification de
[physique_vaisseau_wipeout1.md](../../26-08-24-01/specification/physique_vaisseau_wipeout1.md)
et [physique_vaisseau.md](../../26-08-24-01/specification/physique_vaisseau.md)
par rapport au code réel
([wipeout_ship.gd](../../../../src/scripts/wipeout_ship.gd),
[ship_player.c](../../../../../src/wipeout/ship_player.c),
[ship.c](../../../../../src/wipeout/ship.c),
[ship.h](../../../../../src/wipeout/ship.h)), les formules physiques
principales (magnet, thrust ramp, virage flick, roulis masse-ressort, tangage,
grip/résistance, gravité sol/air) sont fidèlement portées. Les points suivants
restent des pistes d'amélioration, par ordre de priorité décroissante.

## 1. Les raycasts de hover ne filtrent pas par normale — risque de confusion sol/mur

Dans `_sample_hover()`, tous les hits des 4 `RayCast3D` comptent dans
`grounded`/`normal`/`height`, sans filtrer sur `normal.y` — contrairement à
`_handle_wall_collisions()` qui exclut explicitement les normales proches de
la verticale (`absf(normal.y) > 0.45: continue`).

Ces rayons sont des enfants du `Node3D` du vaisseau
(`WipeoutShip.tscn` : `target_position = Vector3(0, -3, 0)`) et tournent donc
avec le roulis/tangage du vaisseau. Après un impact d'aile qui ajoute du
`roll_rate` (voir `_handle_wall_collisions`), un rayon avant peut se retrouver
à taper un mur latéral plutôt que le sol — ce hit sera alors compté comme
« sol » (avec sa normale quasi-horizontale) dans `_apply_hover_forces()`,
faussant `hover.normal`/`hover.height`.

**Suggestion** : ajouter un filtre de normale (proche de la verticale) dans
`_sample_hover()`, symétrique à celui de `_handle_wall_collisions()`, pour ne
compter dans le hover que les hits dont la normale est suffisamment
horizontale (sol/plafond), pas un mur.

## 2. Seuil `grounded` binaire (`hit_count >= 2`), pas d'hystérésis

Pas d'hystérésis entre sol/air : à 2 hits pile (bord de piste, bosse), le
vaisseau peut osciller sol/air d'une frame à l'autre, ce qui fait sauter
`airborne_time` et les branches de calcul (gravité, grip) d'une frame sur
l'autre. L'original n'a pas ce problème car il teste une géométrie de face
continue, pas des rayons discrets.

**Suggestion** : introduire un petit hystérésis (rester « grounded » tant
qu'au moins 1 hit persiste pendant N frames, ou pondérer par la compression
plutôt qu'un simple compte de hits) pour lisser la transition.

## 3. `turn_air_control` est une invention, pas un portage

`steer_accel := turn_accel if grounded else turn_accel * turn_air_control`
(0.9) n'existe pas dans l'original — dans `ship_player.c`, la logique de
virage est identique au sol et en vol. Ce n'est pas un bug, mais c'est un
endroit où la documentation de portage pourrait noter explicitement qu'il
s'agit d'un ajout gameplay plutôt que d'un portage fidèle (actuellement non
mentionné dans `physique_vaisseau_wipeout1.md`).

## 4. Constantes non dérivées d'un facteur d'échelle documenté

Les valeurs `@export` (`hover_force=92`, `track_magnet=1.1`,
`max_resistance=18`...) sont retunées à la main sans facteur de conversion
PSX → Godot explicite (l'original tourne en virgule fixe/unités NTSC à
30 Hz, Godot en mètres/delta-time variable). Les *ratios* sont préservés
(ex. `ground_gravity_scale = 0.375 = 30000/80000`), pas les valeurs absolues.
Ce n'est pas un problème en soi, mais rien ne garantit que ces ratios
resteraient cohérents avec une piste à une échelle différente.

**Suggestion** : documenter en commentaire le facteur d'échelle implicite
(ex. « 1 unité Godot ≈ X unités PSX ») pour figer cette intention.

## Ce qui n'a pas besoin d'être retouché

Le cœur des formules (magnet, thrust ramp, roulis masse-ressort, grip
sol/air, gravité, virage au frein différentiel) est déjà fidèle et solide —
pas de retouche recommandée sans motif de gameplay précis.

Sur ces quatre points, le point 1 est le seul qui ressemble à un défaut de
robustesse plutôt qu'à un choix de design ; c'est le candidat le plus
prioritaire si une correction est souhaitée.
