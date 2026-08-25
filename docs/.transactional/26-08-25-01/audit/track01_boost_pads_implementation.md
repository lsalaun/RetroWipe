# Implémentation — pads de boost fonctionnels

Suite à [track01_decor_and_gameplay_flags_implementation.md](track01_decor_and_gameplay_flags_implementation.md), les pads de vitesse (`boost_pads` de `track_01_face_flags.json`) sont maintenant fonctionnels côté gameplay (auparavant de simples `Marker3D` sans effet).

## 1. Comportement original porté

`ship_player.c` (`ship_player_update_race()`) : tant que la face de piste sous le vaisseau a le flag `FACE_BOOST` (et que le vaisseau n'est pas `SHIP_SPECIALED`), une accélération continue est ajoutée chaque frame :
```c
vec3_t track_direction = vec3_sub(self->section->next->center, self->section->center);
self->velocity = vec3_add(self->velocity, vec3_mulf(track_direction, 30 * system_tick()));
```

## 2. Adaptation Godot

Nouveau script [track_boost_pad.gd](../../../../src/scripts/track_boost_pad.gd) (`TrackBoostPad`, extends `Area3D`) :
- Collision : `collision_layer = 0`, `collision_mask = 64` (même layer que `HullArea` du vaisseau, voir `WipeoutShip.tscn`), `monitorable = false`.
- Forme : `BoxShape3D` générée en code (`box_size` exporté, défaut `Vector3(6, 4, 6)`) — les pads n'ont qu'un centre dans les données exportées, pas d'étendue de face.
- Sur `area_entered` : ajoute une impulsion unique `-ship.global_transform.basis.z * boost_speed` (24 m/s par défaut) à `ship.velocity`.

Écart assumé par rapport à l'original : impulsion ponctuelle à l'entrée plutôt que poussée continue par face de piste tant que le vaisseau reste dessus — l'original raisonne en unités PSX brutes par face de piste (`track_direction` non normalisé, dépendant de l'espacement des sections), ce qui n'a pas d'équivalent direct dans le modèle Godot en mètres/delta-time variable (cf. la note de tuning en tête de `wipeout_ship.gd`). Une impulsion sur une petite zone de déclenchement donne un ressenti équivalent avec un code plus simple.

[track_gameplay_zones.gd](../../../../src/scripts/track_gameplay_zones.gd) instancie désormais un `TrackBoostPad` réel par entrée `boost_pads` (au lieu d'un `Marker3D`) ; les pads d'armes et la grille de départ restent de simples `Marker3D`, faute de système de ramassage/départ à câbler.

## 3. Validation

- Test isolé headless : vaisseau à 5 m/s (velocity forcée) placé sur un `TrackBoostPad` → ~29 m/s après quelques frames physiques (impulsion confirmée, delta cohérent avec `boost_speed = 24`).
- [Track01Test.tscn](../../../../src/scenes/tests/Track01Test.tscn) rejoué en headless avec les 20 pads de boost de `TRACK01` instanciés : code de sortie 0, aucune erreur.

## 4. Limites connues

- `boost_speed`/`box_size` sont des valeurs par défaut non calibrées sur une donnée PSX précise (pas de conversion d'unités fiable disponible, voir le point sur le facteur d'échelle dans [track01_import_gaps_audit.md](track01_import_gaps_audit.md)) — à retoucher au ressenti.
- Aucun cooldown/anti-spam explicite : un repassage sur le même pad redéclenche l'impulsion (comportement jugé acceptable, correspond à l'esprit de l'original qui réapplique la poussée à chaque frame passée sur la face).
- Pads d'armes et grille de départ toujours inertes (hors scope de cette passe).
