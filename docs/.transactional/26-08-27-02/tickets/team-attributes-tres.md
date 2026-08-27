# Attributs d’équipe des vaisseaux — ressources `.tres`

## Résumé

Les caractéristiques des vaisseaux de Wipeout rewrite (table `def.teams` dans `src/wipeout/game.c`) sont désormais portées dans le projet Godot sous forme de ressources `.tres`, une par équipe × classe de course.

Les stats ne sont pas par pilote : les deux pilotes d’une équipe partagent le même fichier. Au spawn, le profil de handling Godot commun (`ShipHandlingProfile`) reste la base physique ; les attributs d’équipe le **scalent** par rapport à AG Systems Venom, sans copier 1:1 les constantes PSX (unités / delta différents).

---

## Source C

`ship_init()` copie, pour le pilote et `g.race_class` :

- `mass`
- `thrust_max`
- `resistance`
- `turn_rate` (argument de `TURN_ACCEL()`)
- `turn_rate_max` (argument de `TURN_VEL()`)
- `skid`

`mass` est 150 pour toutes les équipes. L’IA garde en plus `def.ai_settings` (DPA), inchangé.

---

## Ressources

Dossier : `godot/src/resources/teams/`

| Fichier | Équipe | Classe |
|---|---|---|
| `ag_systems_venom.tres` | AG SYSTEMS | Venom |
| `ag_systems_rapier.tres` | AG SYSTEMS | Rapier |
| `auricom_venom.tres` | AURICOM | Venom |
| `auricom_rapier.tres` | AURICOM | Rapier |
| `qirex_venom.tres` | QIREX | Venom |
| `qirex_rapier.tres` | QIREX | Rapier |
| `feisar_venom.tres` | FEISAR | Venom |
| `feisar_rapier.tres` | FEISAR | Rapier |

Script ressource : `godot/src/scripts/team_attributes.gd` (`class_name TeamAttributes`).

`apply_to()` multiplie sur le vaisseau, relativement à AG Systems Venom (790 / 140 / 160 / 2560 / 12) :

- `mass`
- `thrust_max`
- `resistance`
- `turn_accel` ← `turn_rate`
- `turn_max` ← `turn_rate_max`
- `skid`

---

## Branchement runtime

1. `WipeoutShip._ready()` applique d’abord `handling` (`ShipHandlingProfile`).
2. `WipeoutShip.apply_team_attributes()` réapplique le handling puis overlay le `.tres` d’équipe (idempotent : pas d’empilement si appelé deux fois).
3. `main.gd` charge le `.tres` via `RaceSetup.attributes_for(équipe, RaceSetup.race_class)` pour le joueur (course + time trial) et chaque IA.

Lookup : `RaceSetup.TEAM_ATTRIBUTE_PATHS` + `team_for_pilot()` (noms d’équipe normalisés en majuscules, compatible avec `ShipSelection.SHIPS` qui stocke `"Feisar"` / `"AG Systems"`).

---

## Fichiers ajoutés / modifiés

### Ajoutés

- `godot/src/scripts/team_attributes.gd`
- `godot/src/resources/teams/*.tres` (8 fichiers)
- `godot/src/tools/validate_team_attributes.gd`

### Modifiés

- `godot/src/scripts/race_setup.gd`
- `godot/src/scripts/wipeout_ship.gd`
- `godot/src/scripts/main.gd`

---

## Validation

```text
godot --headless --path godot/src -s res://tools/validate_team_attributes.gd
```

Vérifie que les `.tres` collent à `def.teams`, puis que Feisar Venom tourne plus vite qu’AG, Qirex glisse plus / tourne moins, et Rapier augmente `thrust_max`.

Résultat observé sur `default_profile.tres` : AG Venom `thrust_max=74` / `turn_accel=8.1` / `skid=0.35` ; Feisar Venom `turn_accel=9.11` ; Qirex `skid=0.7` / `turn_accel=6.07` ; Feisar Rapier `thrust_max=112.41`.

---

## Retuning

Éditer le `.tres` de l’équipe/classe. Ne pas y mettre hover, aimant piste, caméra : ça reste dans `resources/handling/*.tres`.
