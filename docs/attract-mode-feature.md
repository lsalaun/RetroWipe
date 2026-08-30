# Implémentation du mode démo/attract mode

## Résumé
Ajout du mode démo automatique qui se lance après 10 secondes d'inactivité sur l'écran titre, mimant le comportement du jeu original en C. Une course pilotée par l'IA s'exécute entièrement sans interaction joueur, avec auto-retour au titre après 60 secondes ou à la première pression de bouton.

## Fonctionnalité
- **Détection d'inactivité** : `TitleScreen` compte 10 secondes sans entrée utilisateur (clavier/souris/gamepad)
- **Lancement automatique** : `RaceSetup.start_attract_mode()` choisit aléatoirement une classe (Venom/Rapier), un pilote et une piste compatible
- **Course entièrement IA** : Les 8 positions de grille sont remplies d'IA ; une porte le flag de référence DPA (`g.pilot` dans l'original) pour le classement et le rubber-banding
- **Caméra itinérante** : Caméra libre qui tire au sort toutes les 5 s entre deux traitements de `camera.c` (orbite autour du sujet / plan fixe au bord de piste, 11 sections en avant) et change de vaisseau suivi à chaque tirage
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

### `src/scripts/attract_camera.gd` (nouveau)
- `AttractCamera` (Camera3D) : port de la chaîne `camera_update_attract_random()`
  - `Mode.ORBIT` = `camera_update_attract_circle` : orbite autour du sujet (~9,6 m de rayon, ~5,6 m de haut)
  - `Mode.STATIC` = `camera_update_static_follow` : point fixe sur la ligne centrale 11 sections en avant, ne fait que pivoter
  - Tirage au sort toutes les 5 s (`VIEW_DURATION`), avec re-sélection du vaisseau sujet
  - Conversions PSX à 106,5 unités/m (échelle établie par `ELECTRO_SHAKE` dans `ship_ai.c`)

### `src/scripts/main.gd`
- `_setup_attract_race()` : remplace le flux normal si `is_attract_mode`
  - Supprime le navire joueur placeholder
  - Crée 8 navires IA (tous `WipeoutShipAI`)
  - Désigne un index aléatoire comme référence DPA (`is_player_controlled = true`, `use_cockpit_audio = false`)
  - Cache le HUD, affiche label "DEMO MODE", désactive le menu pause
- `_add_attract_camera()` : instancie la caméra itinérante et lui passe la grille + la ligne centrale

### `src/scripts/wipeout_ship.gd`
- Nouveau `use_cockpit_audio: bool = true` : découple le mix moteur cockpit du flag `is_player_controlled`
  - Nécessaire car la caméra n'est plus attachée au vaisseau de référence : son moteur doit rester en audio positionnel 3D
  - `_has_cockpit_audio()` remplace les deux tests directs sur `is_player_controlled` dans les chemins audio
- `_process(delta)` / `_unhandled_input()` : gère la durée max (60s) et l'exit sur activité
- `_is_activity_press()` : détecte clés/clic/boutons (motion seule ne compte pas)
- `_exit_attract_mode()` : nettoie le flag et retourne au titre

### `src/scripts/race_director.gd`
- Guard dans `_on_lap_completed()` : skip l'appel à `_end_race()` si attract mode
  - Prevents lap record submission et race_finished signal

## Tests
- ✅ `validate_attract_mode.gd` (nouveau) : vérifie setup, grille, caméra, et comportement de finish
  - Caméra : 40 tirages doivent visiter plusieurs vaisseaux, exercer les deux traitements, et toujours viser le sujet ; un plan STATIC ne dérive pas, un plan ORBIT se déplace
- ✅ `validate_race_logic.gd` : pass (no regressions)
- ✅ `validate_weapon_pads.gd` : pass (no regressions)
- ✅ `validate_audio_volume.gd` : pass (no regressions)

## Écarts assumés vs l'original
- **Sujet de caméra** : `race.c` appelle `camera_update()` avec `g.ships[g.pilot]` à chaque frame, donc l'original suit **un seul** vaisseau pendant toute la démo et ne fait varier que le traitement de caméra. Le changement de sujet à chaque tirage est un ajout de ce port (demandé explicitement).
- **Rayon d'orbite** : oscille dans l'original (base 512 + swing 512 sur le même timer) ; maintenu constant à la somme ici pour un cadrage plus stable.
- Pas de règle `has_shown_attract` (timeout raccourci à ~5 s au 2e déclenchement) — 10 s constant.
- Pas de menu de crédits scrollant (`race.c` l'affiche ~90 % du temps par-dessus la démo).
- `AttractCamera` est référencée par `preload` dans `main.gd` et non par son `class_name` : le cache de classes globales n'est reconstruit qu'à l'import, donc un `class_name` neuf n'est pas résolvable sous `godot -s`.
- Désactiver le pause menu pendant le démo évite les conflits input avec la détection exit
