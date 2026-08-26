# Audit — collisions Godot, adaptées depuis wipeout-rewrite

Date : 2026-08-26

Périmètre : architecture de collisions du port Godot (`godot/src`) en s’appuyant sur wipeout-rewrite (`src/wipeout`) comme **référence de comportement**, pas comme pipeline à cloner.

---

## Objectif

Adapter wipeout-rewrite vers une **architecture Godot**, pas recréer le moteur C.

Cela veut dire :

- garder le **feel** Wipeout (hover collé à la piste, rebond sol, clip nez/aile, contact vaisseau–vaisseau, pads) ;
- s’appuyer sur les nœuds Godot (`Node3D`, `RayCast3D`, `StaticBody3D` trimesh, `Area3D`) ;
- **ne pas** porter `TRACK.TRF` / `ship_collide_with_track()` / `alcol.prm` tels quels.

Le C reste la spec de *quoi* doit arriver (rebond, yaw nez, roll aile, échange de masse). Godot décide *comment* (raycasts, areas, trimesh).

---

## Architecture Godot retenue

| Rôle | Choix Godot | Pourquoi |
|---|---|---|
| Géométrie de piste | `StaticBody3D` + `ConcavePolygonShape3D` (`create_trimesh_shape`) + `backface_collision` | Collider fidèle au mesh importé ; un hull convexe gonfle hors piste et crée de faux murs |
| Vaisseau | `Node3D` cinématique (intégration manuelle de `velocity`) | Même modèle que le C (`position += velocity * dt`) ; un `RigidBody3D` imposerait une physique générique |
| Sol / hover | 4 `RayCast3D` vers le bas | Équivalent Godot de la hauteur au plan de face, sans parser TRF chaque frame |
| Murs | 3 `RayCast3D` latéraux (`WallNose` / `WallWingLeft` / `WallWingRight`) vs trimesh, filtrés par `normal.y` | Les hover rays restent au sol ; les parois verticales sont sondées à l’horizontale (nez puis ailes) |
| Vaisseau–vaisseau | `Area3D` `HullArea` + manager de paires | Overlap Godot à la place de `ship_intersects_ship` / `alcol.prm` |
| Boost / pickups | `Area3D` spawnés depuis `*_face_flags.json` | Les flags TRF sont **pré-exportés**, pas évalués à runtime |

Le `CollisionShape3D` enfant du vaisseau n’est **pas** un corps physique : il ne sert pas à bloquer la piste. C’est voulu. Le vaisseau n’est pas un `CharacterBody3D`. En dernier recours, un `ShapeCast3D` (`HullPenetrationProbe`, même forme que ce `CollisionShape3D`) détecte un chevauchement déjà en cours avec le trimesh et repousse la position hors du mur — toujours pas de corps physique, juste une correction ponctuelle (voir écart 3).

---

## Mapping comportement C → Godot

### 1. Sol / hover

**C** (`ship_player.c`) : distance au plan de la face courante ; bounce `reflect * 0.875` si `height <= 0` ; aimant `TRACK_MAGNET * (FLOAT / height - 1)`.

**Godot** (`wipeout_ship.gd`) : moyenne des 4 rayons ; bounce `0.875` ; aimant porté **en ratio**, pas en unités PSX ; coyote time 80 ms (ajout Godot pour lisser les bords de mesh).

Les rayons trop horizontaux (`|normal.y| < 0.5`) sont ignorés pour le sol : ce n’est pas dans le C, c’est un filtre Godot pour ne pas prendre un mur pour de la piste.

**Statut** : adapté, feel proche. Pas un port 1:1 des constantes NTSC/fixed-point.

### 2. Murs (nez / aile)

**C** : 3 points (nez, aile G, aile D) vs plan de la face mur de la **section courante** ; reflect + recul + `v *= 0.5` + éjection le long de la normale ; yaw (nez) ou roll (aile). `last_impact_time` ne gate que le SFX.

**Godot** : hit mural si `|normal.y| ≤ 0.45` sur un **probe latéral** (`WallNose` puis ailes) ; bounce `* 0.35` + `wall_push_speed` ; yaw nez / roll aile selon `kind` (`nose` / `wing_left` / `wing_right`) ; cooldown 0.12 s désormais limité à l’impulsion de rotation (yaw/roll), l’éjection (bounce/push/damping) se résout **chaque frame** où le probe touche, cooldown ou non.

C’est une **adaptation** : même split nez/aile, autre détection (rayons horizontaux vs trimesh, pas points vs plan TRF). Le cooldown Godot évite le spam de yaw/roll sur trimesh ; le C n’en a pas besoin parce qu’il résout contre une seule face par frame.

**Statut** : probes latéraux en place (joueur + IA). Cooldown restreint au yaw/roll (voir écart 2, fait) ; l’éjection ne peut plus laisser traverser un mur fin pendant le cooldown.

### 3. Vaisseau–vaisseau

**C** : early-out distance ; intersection mesh `alcol.prm` ; échange masse `* 0.5` ; recul de position ; poussée `separation * 4`.

**Godot** (`ship_collision_manager.gd`) : early-out 6 m ; overlap `HullArea` (AABB retunée à 2.0 x 1.0 x 5.4, distincte du placeholder plein gabarit) ; même échange de masse ; poussée `separation * 2.5` ; pas de recul de position.

**Statut** : adapté. La boîte `HullArea` est désormais plus proche du gabarit `alcol.prm` (coarse 4-vertex proxy dans le C) que du mesh visuel complet (voir écart 4, fait). Si les contacts restent trop précoces/tardifs, retuner encore cette boîte, pas réimplémenter les primitives PSX.

### 4. Boost pads

**C** : tant que la face courante a `FACE_BOOST`, `velocity += track_direction * 30 * dt` **chaque frame**.

**Godot** : `Area3D` overlap continu — `velocity += -forward * boost_accel * delta` à chaque frame de chevauchement, positions depuis `*_face_flags.json`.

**Statut** : adapté en trigger Godot continu (voir écart 6, fait). Track 01 / 02 OK. Track 12 : trimesh OK, **pas de `GameplayZones`** — trou d’adaptation, pas un argument pour relire TRF en runtime.

Ce pad continu (tant que overlap) reste Godot-idiomatic et plus proche du C que de parser les faces.

---

## Ce qu’on ne porte pas (volontairement)

| Élément C | Pourquoi Godot s’en passe |
|---|---|
| `track_face_t` / section courante à chaque frame | Remplacé par mesh + raycasts / areas |
| `vec3_is_on_face` / `SECTION_JUNCTION_*` | Le trimesh porte déjà la géométrie des jonctions |
| `alcol.prm` | `HullArea` |
| Unités PSX (`4096`, `0.015625`, distance `960`) | Mètres Godot, constantes re-tunées |
| `SHIP_COLL` / SFX liés à `last_impact_time` | Pas encore branché ; à faire via signaux Godot, pas flags C |

---

## Écarts à traiter (dans le cadre Godot)

Ce sont des **trous d’adaptation**, pas des absences de code C.

1. **Murs** : ~~rayons de hover trop pauvres~~ **fait** — probes `WallNose` / `WallWingLeft` / `WallWingRight` (`_sample_wall_probe`, nez d’abord). Hover rays inchangés (sol uniquement).
2. ~~**Cooldown mural** trop agressif → peut laisser traverser un mur fin~~ **fait** — `_handle_wall_collisions` résout maintenant le bounce/push/damping à chaque frame de contact ; seule l’impulsion de rotation (yaw nez / roll aile) reste gatée par `wall_impact_cooldown_duration` (0.12 s).
3. **Hull inerte** : normal pour un `Node3D` cinématique ; ~~si pénétration, corriger par probes, pas par `CharacterBody3D.move_and_slide`~~ **fait** — `HullPenetrationProbe` (`ShapeCast3D`, même `BoxShape3D` que le hull) détecte un chevauchement déjà en cours avec le trimesh et repousse la position le long de la normale de contact (`_resolve_hull_penetration`), sans introduire de corps physique.
4. ~~**Ship–ship** : AABB plus large que `alcol.prm`~~ **fait** — `HullArea` a maintenant sa propre `BoxShape3D` (2.0 x 1.0 x 5.4) séparée du placeholder plein gabarit (3.4 x 1.5 x 7.9, mesuré égal à l'AABB réelle du modèle importé), pour ne plus déclencher un contact sur les extrémités (nez/ailes) comme le ferait la boîte pleine taille.
5. **Track 12** : brancher `GameplayZones` + `track_*_face_flags.json` comme Track 01 / 02.
6. ~~**Boost** : option overlap continu plutôt que one-shot~~ **fait** — `TrackBoostPad._physics_process` applique maintenant `velocity += -forward * boost_accel * delta` à chaque frame de chevauchement (via `get_overlapping_areas()`), toujours en `Area3D`, au lieu d'une impulsion unique sur `area_entered`.
7. **SFX** : `area_entered` / impact mural → `AudioStreamPlayer3D`, pas un port de `sfx_play_at`.

---

## Tableau (adaptation, pas fidélité 1:1)

| Sous-système | Adaptation Godot | Feel vs C | Suite |
|---|---|---|---|
| Collider piste trimesh + backface | Fait, bon choix | Solide | Garder ; ne pas passer en convex |
| Hover / bounce sol | Fait | Proche | Fine-tune constantes |
| Murs nez / aile | Fait (probes latéraux + éjection non gatée par le cooldown + `HullPenetrationProbe` en dernier recours) | Proche | SFX |
| Vaisseau–vaisseau | Fait (Area3D, boîte retunée 2.0x1.0x5.4) | Proche | Ajuster si besoin |
| Boost | Fait (Area3D, overlap continu) | Proche | Retuner `boost_accel` au ressenti |
| Jonctions TRF | Non porté, volontaire | N/A | Trimesh suffit |
| SFX collision | Pas encore | Absent | Signaux Godot |
| Track 12 pads | Manquant | Absent | Copier le pattern Track 01/02 |

---

## Recommandation

Rester sur l’architecture actuelle (`Node3D` + trimesh + raycasts + areas).

Ne pas réintroduire :

- un parseur TRF runtime,
- `ship_collide_with_track()` point-vs-plan,
- un `RigidBody3D` pour “avoir des collisions Godot”.

Priorités d’adaptation :

1. `GameplayZones` sur Track 12.
2. SFX d’impact via nœuds audio.

---

## Fichiers de référence

### Spec comportement (C)

- `src/wipeout/ship.c` — murs, vaisseau–vaisseau
- `src/wipeout/ship_player.c` — hover, bounce, boost
- `src/wipeout/track.h` — flags (exportés vers JSON, pas lus en jeu)

### Implémentation Godot

- `godot/src/scripts/wipeout_ship.gd`
- `godot/src/scripts/track_mesh_collider.gd`
- `godot/src/scripts/ship_collision_manager.gd`
- `godot/src/scripts/track_boost_pad.gd` / `track_gameplay_zones.gd`
- `godot/src/scenes/WipeoutShip.tscn`
- `godot/src/scenes/Track01.tscn`, `Track02.tscn`, `Track12.tscn`
