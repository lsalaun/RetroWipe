# HUD en jeu et logique de course

## Résumé
Implémentation complète du HUD en jeu et de la logique de course portée de `src/wipeout/hud.c` et `src/wipeout/ship.c`. Inclut le rendu texte bitmap original (DRFONTS), la détection des tours avec ligne d'arrivée exacte, le décompte de départ, l'écran de résultats de fin de course, et la persistance des records de tours.

## Changements

### Nouveaux scripts
- **`wipeout_ui.gd`** — Système de rendu texte bitmap
  - Charge et dessine les trois atlas DRFONTS (`drfonts_00/01/02.png`)
  - Tables d'offsets/largeurs exactes de `char_set` depuis `ui.c`
  - Mapping `char_to_glyph_index()` avec alias `'e'`→`:` et `'f'`→`.`
  - Format `MM:SS.T` pour `ui_draw_time()`
  - Couleurs `UI_COLOR_ACCENT` (jaune doré) et `UI_COLOR_DEFAULT` (blanc)

- **`race_director.gd`** — Chef d'orchestre de la course
  - États : `COUNTDOWN` (grille bridée) → `RACING` (contrôle libéré) → `FINISHED`
  - Décompte 3/2/1/GO avec sons (`UPDATE_TIME_*` de `ship.h`)
  - Grille bridée (`race_control_enabled = false`) : physique active, entrées neutres
  - Ranking et statistiques de fin de course (`race_end()`)
  - Persistance du record de tour par circuit/classe

- **`race_hud.gd`** — HUD pendant la course
  - Compteur `LAP n OF 3` aux coordonnées originales
  - Temps courant + tours précédents empilés (accent jaune)
  - `POSITION` (rang) caché en time trial
  - `LAP RECORD` du circuit courant
  - Avertissement `WRONG WAY` + décompte affiché

- **`race_results.gd`** — Écran de fin de course
  - Titre `CONGRATULATIONS` / `FAILED TO QUALIFY`
  - Portrait du pilote (qualifié/non qualifié)
  - Rang de course et trois temps de tours
  - Temps total et meilleur tour
  - Boutons RESTART RACE / QUIT TO MENU

### Modifications existantes
- **`wipeout_ship.gd`** — Logique de tours
  - Signal `lap_completed(ship, lap_index: int, time: float)`
  - `lap` : −1 (avant franchissement) → 0+ (tours numérotés)
  - `max_lap` : plus haut tour atteint (empêche re-chronométrage)
  - `lap_time` : cumulatif par tour, réinitialisé sur franchissement
  - `lap_times: Array[float]` : enregistrement par tour
  - `start_line_offset` : distance le long de la centerline (dérivée de `start_line_pos`)
  - `direction_forward` : détection du sens (HUD `WRONG WAY`)
  - `is_racing` / `race_control_enabled` : drapeaux de contrôle du jeu
  - Détection de franchissement par distance signée (résout l'ambiguïté du wrapping)
  - Méthode `reset_race_state()` pour restart sans reconstruire le vaisseau

- **`wipeout_ship_ai.gd`** — Grille de départ
  - Bypass DPA et `_pull_to_racing_line()` si `race_control_enabled == false`
  - Maintient `start_accelerate_timer` pendant le décompte

- **`race_field.gd`** — Ranking
  - Ne met à jour les rangs que si le joueur n'a pas terminé (`is_racing == true`)
  - Figé sur l'écran de résultats

- **`track_selection.gd`** — Métadonnées de circuit
  - Ajout `start_line` par track (section TRACK.TRS, game.c `start_line_pos`)
  - Méthodes `start_line_section_for()` / `selected_start_line_section()`

- **`main.gd`** — Intégration
  - Calcul `start_line_offset` via centerline (courbe point ≈ section)
  - Transmission à tous les vaisseaux

- **`settings.gd`** — Persistance
  - `lap_records: Dictionary` (clé : `"CIRCUIT|CLASS|TAB"`)
  - `get_lap_record()` / `submit_lap_record()` avec défauts de `game.c`
  - Toggle FPS optionnel

- **`options_video_menu.gd`** — UI
  - Ajout toggle `SHOW FPS` aux options vidéo

- **`RaceHud.tscn`** — Scène HUD
  - Nœud `Hud` (Control) contient le texte bitmap + speedo
  - Nœud `Results` (Control) affiche l'écran de fin

- **`main.tscn`** — Scène principale
  - Ajout `RaceDirector` node avec groupe `race_director`

### Validateurs
- **`validate_race_logic.gd`** (nouveau) — Tests headless
  - Métriques de police bitmap (widths, `format_time()`)
  - Comptage de tours sur courbe fermée synthétique (4 franchissements, max_lap, marche arrière)
  - Câblage `main.tscn` (grille bridée, débloquée, offset de ligne)

- **`validate_ai_field.gd`** — Augmenté
  - `WAIT_FRAMES`: 180 → 600 (décompte + marge)

- **`validate_ui_art.gd`** — Augmenté
  - Nœuds RaceHud (`Hud/Speedo/Facia`, `Results`)
  - Atlases DRFONTS via `WipeoutUI.ATLAS_PATHS`

## Comportement

### Démarrage
1. Joueur/IA spawn dans la grille (15 sections avant la ligne)
2. RaceDirector entre `COUNTDOWN` (6.7 s : 200/30)
3. Tous les vaisseaux ont `race_control_enabled = false` → entrées neutres, physique active pour descendre
4. Décompte 3/2/1/GO (sons + HUD)
5. RaceDirector bascule → `RACING` + déverrouille grille

### Course
- Chaque franchissement avant de la ligne : `lap += 1`
- Premier franchissement d'un nouveau lap (`lap > max_lap`) : banque temps + émet `lap_completed`
- Franchissement arrière : `lap -= 1` (mais time déjà banqué, max_lap la protège)
- `direction_forward` = oui si le nez pointe en avant le long la piste

### Fin
- Joueur franchit ligne sur lap 3 : `race_end()`
- Calcule temps total (somme des laps), meilleur tour
- Vérifie record (persiste si < standing)
- Affiche résultats avec portrait
- Ranking figé

## Notes
- Décompte 6.7 s imposé fidèle à `game.c` (pas d'intro caméra pour le justifier). Réglable via `RaceDirector.COUNTDOWN_START` si long pour les tests.
- Portrait fallback : `ShipSelection.SHIPS[0]` si pilote non trouvé.
- 11 validateurs headless passent.
- Tous les records par défaut repris de `game.c` (3599.99 = "unbeatable").
