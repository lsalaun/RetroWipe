# Audit — gestion des collisions Godot vs wipeout-rewrite

Date : 2026-08-26

Périmètre : port Godot `D:\code\wipeout-rewrite\godot` comparé au moteur C `D:\code\wipeout-rewrite\src\wipeout`.

---

## Verdict

Le port Godot **reprend l’intention** des collisions Wipeout (sol / mur nez-aile / vaisseau–vaisseau), mais **ce n’est pas le même moteur**.

- L’original est un système **géométrique par faces de piste** (`TRACK.TRF`).
- Godot est un système **RayCast + trimesh + Area3D**, avec des approximations importantes.

---

## 1. Piste (sol + murs)

### wipeout-rewrite

Sources : `src/wipeout/ship.c`, `src/wipeout/ship_player.c`, `src/wipeout/track.h`.

- La piste est une liste de **faces** (`track_face_t`) : sol (`FACE_TRACK_BASE`) vs murs.
- Le vaisseau connaît sa **section courante**.
- `ship_collide_with_track()` teste **3 points** contre le **plan du mur** :
  - nez `ship_nose` = `(0, 0, 512)`
  - aile gauche `(-256, 0, -256)`
  - aile droite `(256, 0, -256)`
- Collision = **distance signée au plan ≤ 0**.
- Aux jonctions (`SECTION_JUNCTION_*`), un test supplémentaire `vec3_is_on_face()` évite les faux positifs.
- Le boost est **continu** tant que la face a `FACE_BOOST`.

### Godot

Sources : `godot/src/scripts/track_mesh_collider.gd`, `godot/src/scripts/wipeout_ship.gd`.

- Le mesh de piste devient un `StaticBody3D` **trimesh** avec `backface_collision = true` (bon choix : pas de hull convexe gonflé).
- Le vaisseau est un `Node3D` **sans** `CharacterBody3D` / `RigidBody3D` : le moteur physique Godot **ne pousse pas** le hull contre la piste.
- Sol et murs passent par **4 RayCast3D vers le bas** (`HoverFront/Rear Left/Right`).
- Un hit est **sol** si `|normal.y| ≥ 0.5`, **mur** si `|normal.y| ≤ 0.45`.

### Écarts

- Pas de faces TRF, pas de section courante, pas de logique de jonction.
- Les murs ne sont pas testés avec nez/ailes dédiés, mais avec des rayons **verticaux** qui touchent parfois un mur.
- `Track12.tscn` n’a **pas** de `GameplayZones` (pas de pads boost).
- Le `CollisionShape3D` du vaisseau est un enfant de `Node3D` : **inerte**, il ne collisionne rien.

Le trimesh + backface est aligné avec le gotcha déjà noté : un hull convexe déborde de la piste et crée de faux contacts muraux.

---

## 2. Collision sol (hover / bounce)

### Original (`ship_player.c`)

- Hauteur = distance au **plan de la face**.
- `height <= 0` : `reflect(v, n, 2)` puis `* 0.875`, plus une poussée `-n * 64`.
- `height < 30` : petite poussée vers le haut.
- Aimant de piste : `TRACK_MAGNET * (FLOAT / height - 1)`.

### Godot

- Hauteur = moyenne des 4 rayons.
- Bounce `0.875` si `height <= 0` : **fidèle en ratio**.
- Aimant de piste porté en ratio, pas en unités PSX.
- **Coyote time** 80 ms (ajout Godot, absent de l’original).
- Les rayons trop horizontaux sont ignorés pour le sol (filtre anti-mur).

C’est la partie **la plus proche** de l’original, au niveau comportement.

---

## 3. Collision murs

### Original

`ship_resolve_nose_collision` / `ship_resolve_wing_collision` :

1. `velocity = reflect(v, face.normal, 2)`
2. Recul de position `v * 0.015625`
3. Amortissement `v *= 0.5`
4. Éjection `v += face.normal * 4096`
5. **Nez** → yaw (`angular_velocity.y`)
6. **Aile** → roll (`angular_velocity.z`)
7. `last_impact_time` **ne bloque pas** la collision : il ne gate que le SFX (`> 0.2 s`)

### Godot (`_handle_wall_collisions`)

1. Bounce `* 0.35` (beaucoup plus mou que reflect 2 + 0.5)
2. `+ normal * wall_push_speed` (18)
3. Perte de vitesse avant
4. Nez vs aile selon l’offset latéral (`wall_nose_hit_width = 0.58`)
5. **Cooldown 0.12 s qui skippe toute la résolution**

### Écarts majeurs

- Classification nez/aile approximative (offset latéral du rayon, pas les 3 points du modèle).
- Pas de recul de position.
- Le cooldown **empêche** les collisions répétées ; l’original continue de résoudre chaque frame.
- Pas de sons d’impact.

---

## 4. Collision vaisseau–vaisseau

### Original (`ship_collide_with_ship`)

- Early-out distance `960`.
- Intersection **réelle** via `collision_model` (`alcol.prm`, 4 points + primitives).
- Échange de vitesse pondéré par masse, puis `* 0.5`.
- Recul de position, puis poussée `separation * 4`.
- Flag `SHIP_COLL` + SFX crunch.

### Godot (`ship_collision_manager.gd`)

- Early-out `6 m`.
- Overlap de `HullArea` (boîte `3.4 × 1.5 × 7.9`, layer 64).
- Même idée masse / `* 0.5`.
- Poussée `separation * 2.5`.
- **Pas** de recul de position, **pas** de mesh `alcol.prm`.

La résolution vitesse est **conceptuellement portée**. La détection est une **AABB**, pas le mesh de collision PSX.

---

## 5. Boost pads

| | Original | Godot |
|---|---|---|
| Détection | face courante `FACE_BOOST` | `Area3D` one-shot |
| Force | `track_direction * 30 * dt` **chaque frame** | `+forward * 24` **une fois** à l’entrée |
| Direction | axe de la **section** | `-basis.z` du vaisseau |

Sur Track 01 / 02, les pads sont spawnés depuis `*_face_flags.json`. Track 12 n’en a pas.

---

## Tableau de fidélité

| Sous-système | Fidélité | Commentaire |
|---|---|---|
| Collider piste trimesh + backface | Bon | Évite les faux murs d’un hull convexe |
| Hover / bounce sol | Bon | Ratios portés, pas les unités PSX |
| Murs nez / aile | Moyen | Même idée, autre détection et autre réponse |
| Vaisseau–vaisseau | Moyen | Même échange de masse, autre shape |
| Boost | Faible | One-shot vs continu le long de la section |
| Jonctions / faces TRF | Absent | Pas de `ship_collide_with_track` |
| SFX collision | Absent | `last_impact_time` / crunch non portés |
| Track 12 gameplay zones | Absent | Pas de pads |

---

## Risques concrets en jeu

1. **Murs ratés ou collants** : un RayCast vers le bas peut ne jamais voir un mur vertical, ou le voir trop tard.
2. **Le cooldown Godot** peut laisser le vaisseau **traverser** un mur fin si le premier hit n’éjecte pas assez.
3. **Le hull n’est pas un corps physique** : rien n’empêche une pénétration si les rayons / areas ratent.
4. **Ship–ship** : les boîtes sont plus grosses / plus simples que `alcol.prm` → contacts plus précoces, moins “pointus”.
5. **Track 12** : collisions mesh OK, mais **aucun pad**.

---

## Recommandation

En résumé : Godot **imite** Wipeout rewrite, il ne **reproduit pas** le pipeline faces/nez/ailes.

Pour se rapprocher vraiment :

- tester des points nez/ailes contre les faces mur du JSON (comme `ship_collide_with_track`) ;
- ne plus se servir des rayons de hover pour les murs ;
- éventuellement porter le recul de position et le SFX d’impact ;
- ajouter les `GameplayZones` manquantes sur Track 12.

---

## Fichiers de référence

### Original C

- `src/wipeout/ship.c` — `ship_collide_with_track`, `ship_resolve_nose_collision`, `ship_resolve_wing_collision`, `ship_collide_with_ship`, `ship_intersects_ship`
- `src/wipeout/ship_player.c` — hover, bounce sol, boost `FACE_BOOST`
- `src/wipeout/track.h` — flags de faces / sections

### Port Godot

- `godot/src/scripts/wipeout_ship.gd` — hover, bounce, `_handle_wall_collisions`
- `godot/src/scripts/track_mesh_collider.gd` — trimesh + backface
- `godot/src/scripts/ship_collision_manager.gd` — vaisseau–vaisseau
- `godot/src/scripts/track_boost_pad.gd` / `track_gameplay_zones.gd` — pads
- `godot/src/scenes/WipeoutShip.tscn` — RayCasts + HullArea
- `godot/src/scenes/Track01.tscn`, `Track02.tscn`, `Track12.tscn`
