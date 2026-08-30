# Implémentation du mode démo/attract mode

## Résumé
Ajout du mode démo automatique qui se lance après 10 secondes d'inactivité sur l'écran titre, mimant le comportement du jeu original en C. Une course pilotée par l'IA s'exécute entièrement sans interaction joueur, avec auto-retour au titre après 60 secondes ou à la première pression de bouton.

## Fonctionnalité
- **Détection d'inactivité** : `TitleScreen` compte 10 secondes sans entrée utilisateur (clavier/souris/gamepad)
- **Lancement automatique** : `RaceSetup.start_attract_mode()` choisit aléatoirement une classe (Venom/Rapier), un pilote et une piste compatible
- **Course entièrement IA** : Les 8 positions de grille sont remplies d'IA ; une est désignée POV pour la caméra
- **Interface masquée** : HUD caché, label "DEMO MODE" affiché, menu pause désactivé
- **Retour au titre** : Après 60s (hard cap `race.c`) ou première pression de bouton réelle (clé/clic/bouton manette)
- **Protection des records** : Un "finish" de démo ne soumet pas de record lap ni ne déclenche l'écran résultats

## Fichiers modifiés

### `src/scripts/title_screen.gd`
- Ajout `_idle_time` tracker et `IDLE_TIMEOUT = 10.0`
- Réinitialisation du compteur sur chaque `_unhandled_input()` / `_gui_input()`
- `_process(delta)` déclenche `RaceSetup.start_attract_mode()` au timeout

### `src/scripts/race_setup.gd`
- Ajout `is_attract_mode: bool = false` (flag global)
- Fonction `start_attract_mode(tree)` : pick aléatoire classe/pilote/piste, puis `tree.change_scene_to_file(RACE_SCENE)`

### `src/scripts/track_selection.gd`
- Fonction `random_track_scene_for(race_class)` : sélection aléatoire d'une piste correspondant à la classe

### `src/scripts/main.gd`
- `_setup_attract_race()` : remplace le flux normal si `is_attract_mode`
  - Supprime le navire joueur placeholder
  - Crée 8 navires IA (tous `WipeoutShipAI`)
  - Désigne le dernier comme POV (`is_player_controlled = true`, caméra active)
  - Cache le HUD, affiche label "DEMO MODE", désactive le menu pause
- `_process(delta)` / `_unhandled_input()` : gère la durée max (60s) et l'exit sur activité
- `_is_activity_press()` : détecte clés/clic/boutons (motion seule ne compte pas)
- `_exit_attract_mode()` : nettoie le flag et retourne au titre

### `src/scripts/race_director.gd`
- Guard dans `_on_lap_completed()` : skip l'appel à `_end_race()` si attract mode
  - Prevents lap record submission et race_finished signal

## Tests
- ✅ `validate_attract_mode.gd` (nouveau) : vérifie setup, grille, et comportement de finish
- ✅ `validate_race_logic.gd` : pass (no regressions)
- ✅ `validate_weapon_pads.gd` : pass (no regressions)  
- ✅ `validate_audio_volume.gd` : pass (no regressions)

## Notes
- Pas de caméra itinérante multi-navires (complexité = hors scope)
- Pas de règle "has_shown_attract" (timeout court au 2e appel) — juste 10s constant
- Désactiver le pause menu pendant le démo évite les conflits input avec la détection exit
