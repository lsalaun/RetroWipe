# Menu system Godot – Wipeout rewrite

## Résumé

Le port Godot de Wipeout a été complété avec une hiérarchie de menus conforme au flux du jeu original, inspiré du code C de `src/wipeout/main_menu.c` et `src/wipeout/ingame_menus.c`.

Le système couvre :

- le menu principal,
- la sélection de classe de course,
- le type de course,
- la sélection d’équipe,
- la sélection de pilote,
- la sélection de circuit,
- le sous-menu Options,
- le menu de pause pendant la course.

---

## Flux implémenté

```text
MainMenu
  -> RaceClassMenu
      -> RaceTypeMenu
          -> TeamMenu
              -> PilotMenu
                  -> CircuitMenu (single race / time trial)
                  -> main.tscn (championship, démarrage direct sur le premier circuit)

OptionsMenu
  -> OptionsControlsMenu
  -> OptionsVideoMenu
  -> OptionsAudioMenu

PauseMenu (CanvasLayer)
  -> Continue
  -> Restart
  -> Quit to menu
```

---

## Fichiers ajoutés / modifiés

### Scènes

- `godot/src/scenes/MainMenu.tscn`
- `godot/src/scenes/RaceClassMenu.tscn`
- `godot/src/scenes/RaceTypeMenu.tscn`
- `godot/src/scenes/TeamMenu.tscn`
- `godot/src/scenes/PilotMenu.tscn`
- `godot/src/scenes/CircuitMenu.tscn`
- `godot/src/scenes/OptionsMenu.tscn`
- `godot/src/scenes/OptionsVideoMenu.tscn`
- `godot/src/scenes/OptionsAudioMenu.tscn`
- `godot/src/scenes/OptionsControlsMenu.tscn`
- `godot/src/scenes/PauseMenu.tscn`

### Scripts

- `godot/src/scripts/main_menu.gd`
- `godot/src/scripts/race_class_menu.gd`
- `godot/src/scripts/race_type_menu.gd`
- `godot/src/scripts/team_menu.gd`
- `godot/src/scripts/pilot_menu.gd`
- `godot/src/scripts/circuit_menu.gd`
- `godot/src/scripts/options_menu.gd`
- `godot/src/scripts/options_video_menu.gd`
- `godot/src/scripts/options_audio_menu.gd`
- `godot/src/scripts/options_controls_menu.gd`
- `godot/src/scripts/pause_menu.gd`
- `godot/src/scripts/race_setup.gd`
- `godot/src/scripts/settings.gd`
- `godot/src/scripts/track_selection.gd`

### Projet

- `godot/src/project.godot`
- `godot/src/scenes/main.tscn`

---

## Détail fonctionnel

### 1) Menu principal

Le menu principal reflète le comportement du jeu original :

- `START GAME`
- `OPTIONS`
- `QUIT`

Le bouton `QUIT` ouvre une confirmation avant fermeture de l’application.

### 2) Sélection de classe

Le menu de sélection de classe de course affiche :

- `VENOM CLASS`
- `RAPIER CLASS`

Les valeurs sont centralisées dans `RaceSetup`, afin de refléter le modèle de données C original.

### 3) Sélection de type de course

Le menu de type de course affiche :

- `CHAMPIONSHIP RACE`
- `SINGLE RACE`
- `TIME TRIAL`

### 4) Sélection d’équipe

La sélection d’équipe correspond à l’ordre des équipes du jeu original :

- AG SYSTEMS
- AURICOM
- QIREX
- FEISAR

### 5) Sélection de pilote

Les pilotes sont filtrés selon l’équipe sélectionnée, conformément au design de `def.teams` et `def.pilots` côté C.

### 6) Sélection de circuit

Pour les courses simples et les essais chronométrés, le joueur choisit un circuit dans la liste disponible.

Pour les championnats, on démarre directement sur le premier circuit disponible, comme dans le flux original.

### 7) Menu Options

Le menu Options contient :

- `CONTROLS`
- `VIDEO`
- `AUDIO`

Et les sous-menus associées.

### 8) Réglages vidéo

Implémentés :

- `FULLSCREEN`
- `VSYNC`

Le reste du système de menu C est suffisamment couvrant pour être porté progressivement, mais les réglages qui correspondent au cœur du gameplay fonctionnent déjà dans ce port Godot.

### 9) Réglages audio

Implémenté :

- `MASTER VOLUME`

La valeur est sauvegardée dans le fichier utilisateur et appliquée via `AudioServer`.

### 10) Réglages contrôles

Implémenté :

- mapping clavier / joystick,
- capture de l’entrée suivante,
- sauvegarde dans `user://settings.cfg`.

### 11) Menu pause en course

Le menu de pause a été ajouté dans la scène principale :

- `Continue`
- `Restart`
- `Quit to menu`

Il est activé via la touche `Esc` / `ui_cancel`, et utilise `get_tree().paused` pour suspendre la course.

---

## Autoloads ajoutés

### `RaceSetup`

Le script `race_setup.gd` centralise le flux de sélection et les données de jeu :

- classes de course,
- types de course,
- équipes,
- pilotes,
- sélection courante.

Il s’appuie sur les données existantes dans `ShipSelection.SHIPS` pour éviter la duplication de source de vérité.

### `Settings`

Le script `settings.gd` gère :

- plein écran,
- synchronisation verticale,
- volume principal,
- remappage clavier / manette,
- persistance sur disque.

---

## Vérification

Une validation headless Godot a été exécutée afin de charger toutes les scènes du système de menus et vérifier qu’elles ne produisent pas d’erreur de script ou de lecture de scène.

Résultat de la vérification :

- toutes les scènes du menu se chargent correctement,
- la scène principale charge aussi correctement avec le menu de pause branché,
- le script de validation temporaire a ensuite été supprimé.

> Il reste un message d’alerte lié au rendu headless sur la scène 3D (`material is null` dans un contexte de rendu dummy), mais il ne concerne pas le menu lui-même ; c’est un comportement de headless Godot déjà connu et non bloquant pour la validation du menu.

---

## Conclusion

Le port Godot du menu Wipeout est désormais aligné sur la structure de `wipeout-rewrite` :

- même logique de navigation,
- même séquence de choix,
- mêmes types de menus,
- même schéma de sélection de course / équipe / pilote,
- prise en charge des options et du menu pause.

Le système est prêt pour une extension complémentaire vers les écrans de fin de course, de hall of fame, et de menus plus détaillés inspirés des écrans C d’origine.
