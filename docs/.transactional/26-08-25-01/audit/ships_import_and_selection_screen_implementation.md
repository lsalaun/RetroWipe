# Implémentation — import des vaisseaux, intégration jeu, écran de sélection

Suite à [convert_ships_implementation.md](convert_ships_implementation.md) (script de conversion), les 8 vaisseaux sont maintenant importés, intégrés au jeu Godot, et sélectionnables via un nouvel écran.

## 1. Import exécuté

`convert_ships.py` exécuté sur `COMMON/ALLSH.PRM` + `COMMON/ALLSH.CMP` → 8 glTF texturés, convertis en `.glb` autonomes via [convert_track_mesh.py](../../../../tools/blender/convert_track_mesh.py) (Blender headless), installés dans `src/assets/ships/<nom>/<nom>.glb` :
`sophia`, `solaar`, `jacko`, `chang`, `arian`, `arial`, `anasta`, `Dekka` (noms tirés directement des données PSX, un objet PRM par vaisseau).

## 2. Intégration dans WipeoutShip

- [wipeout_ship.gd](../../../../src/scripts/wipeout_ship.gd) : nouveau `@export var ship_model_scene: PackedScene` + nœud `ShipVisual` (mount point) + méthode `set_ship_model(scene)` qui masque le `BodyMesh` placeholder (boîte primitive) et instancie le modèle importé à la place. Appliqué automatiquement dans `_ready()` si `ship_model_scene` est déjà défini à l'édition.
- Nœud `ShipVisual` ajouté à [WipeoutShip.tscn](../../../../src/scenes/WipeoutShip.tscn) et [WipeoutShipAI.tscn](../../../../src/scenes/WipeoutShipAI.tscn) (méthode héritée via `WipeoutShipAI extends WipeoutShip`).
- [main.gd](../../../../src/scripts/main.gd) : après positionnement des vaisseaux sur la grille, applique `ShipSelection.selected_ship_scene` uniquement au vaisseau `is_player_controlled` — les IA gardent leur placeholder.

## 3. Écran de sélection

Nouveau pattern miroir de `TrackSelection`/`MainMenu` déjà existant :
- [ship_selection.gd](../../../../src/scripts/ship_selection.gd) (autoload `ShipSelection`, enregistré dans `project.godot`) : liste `SHIPS` (pilote, équipe, chemin du mesh), `select_ship(path)`. Pilotes/équipes vérifiés dans `game.c` (`def.pilots`, `def.teams`) et associés aux noms d'objets PRM par correspondance directe (ex. `sophia` → Sofia De La Rente / Feisar).
- [ShipSelectionMenu.tscn](../../../../src/scenes/ShipSelectionMenu.tscn) + [ship_selection_menu.gd](../../../../src/scripts/ship_selection_menu.gd) : un bouton par pilote, sélectionne puis lance `main.tscn`.
- [main_menu.gd](../../../../src/scripts/main_menu.gd) : la sélection de piste redirige désormais vers `ShipSelectionMenu.tscn` au lieu de `main.tscn` directement.

Flux complet : `MainMenu` (piste) → `ShipSelectionMenu` (pilote) → `main.tscn`.

## 4. Validation

- Réimport headless des 8 `.glb` : propre, aucune erreur.
- Test bout-en-bout (script headless temporaire) : `ShipSelection.select_ship("sophia")` puis instanciation de `main.tscn` → le vaisseau joueur a `body_mesh.visible=false` et `ship_visual` contient bien le modèle importé (1 enfant), tandis que le vaisseau IA reste inchangé (`body_mesh.visible=true`, `ship_visual` vide) — confirme l'isolation joueur/IA.
- Non-régression : `Track01Test.tscn` toujours propre (code de sortie 0) après tous les changements.
- Une erreur de rendu ("Parameter material is null") apparaît après `quit()` dans le test headless — artefact connu du driver de rendu factice en mode headless lors de la libération de matériaux importés, sans rapport avec la logique de sélection (survient après l'obtention des résultats de validation).

## 5. Limites connues / suites possibles

- Échelle du modèle importé non calibrée visuellement contre la `CollisionShape3D`/`HullArea` existantes (dimensionnées pour le placeholder) — à ajuster si le vaisseau apparaît trop grand/petit ou mal aligné avec la coque physique.
- Seul le vaisseau du joueur reçoit la sélection ; les vaisseaux IA gardent le placeholder (hors scope de cette passe).
- Pas de tri/filtrage par équipe ni de portrait dans l'écran de sélection (texte seul, `"pilote (équipe)"`).
- Les modèles de collision (`ALCOL.PRM`/`ALCOL.CMP`) ne sont pas utilisés ; la collision du vaisseau reste la boîte simplifiée existante.
