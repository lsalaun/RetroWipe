# Audit — éléments de TRACK01 non traités par le pipeline d'import PSX

État de l'import PSX->Godot du circuit `TRACK01` (voir
[convert_track_geometry.py](../../../../tools/psx_track/convert_track_geometry.py),
[convert_track_sections.py](../../../../tools/psx_track/convert_track_sections.py),
[convert_track_mesh.py](../../../../tools/blender/convert_track_mesh.py)),
comparé au contenu réel du dossier `wipeout/TRACK01` et à ce que le moteur
`wipeout-rewrite` (`src/wipeout/*.c`) charge effectivement pour ce circuit.

## 1. Ce qui est importé aujourd'hui

- `TRACK.TRV` + `TRACK.TRF` → géométrie de la piste (mesh, groupée par id de
  texture).
- `LIBRARY.CMP` + `LIBRARY.TTF` → textures de la piste (tuiles 128x128
  assemblées depuis les sous-tuiles 32x32 décompressées).
- `TRACK.TRS` → ligne de centre (chaîne de sections, consommée par
  `track_center_line.gd`).

## 2. Utilisé par le moteur, mais pas encore porté

- **`SKY.CMP` + `SKY.PRM`** — modèle et textures du ciel/fond de décor
  (dôme de skybox), chargés par `scene_load()` dans `scene.c`.
- **`SCENE.CMP` + `SCENE.PRM`** — objets de décor en bord de piste :
  tribunes (`stad_`/`lostad_`/`newstad_`), portiques de départ (`start*`),
  pompes à huile (`donkey*`), feux rouges (`redl*`) — voir `scene_load()`
  dans `scene.c`. Aucun script ne lit le format `.PRM` (modèles/objets) côté
  Godot pour l'instant.
- **Flags de face déjà présents dans `TRACK.TRF`**, mais ignorés par
  `convert_track_geometry.py` : `FACE_PICKUP_LEFT`/`FACE_PICKUP_RIGHT`
  (pads d'armes), `FACE_BOOST` (pads de boost), `FACE_START_GRID` (grille de
  départ). La géométrie de ces faces est importée, mais rien ne marque leur
  rôle de gameplay dans le mesh/JSON exporté.
- **Sections `SECTION_JUMP`** (2 détectées dans `TRACK.TRS` pour ce
  circuit) — utilisées par le moteur (`droid_init()` dans `droid.c`) pour
  positionner le droïde de secours ; exportées dans `section_flags` par
  `convert_track_sections.py` mais pas encore exploitées côté Godot.

## 3. Fichiers présents dans `TRACK01` mais jamais référencés dans le moteur

Recherché sans résultat dans l'ensemble de `src/wipeout/*.c` :
`ICONS.TEX`, `LIBRARY.H`, `LIBRARY.INF`, `LIBRARY.TEX`, `SCENE.INF`,
`SCENE.TEX`, `SKY.INF`, `SKY.TEX`, `STATE.RST`, `TRACK.CMP`, `TRACK.INF`,
`TRACK.VEW`.

Ces fichiers semblent être des artefacts de production PSX (en-têtes/infos
de tooling d'époque, formats alternatifs superseded par `.CMP`/`.PRM`/`.TTF`)
que même le rewrite fidèle du moteur n'utilise pas. Aucune action requise
sauf si une source fiable en documente un usage caché.

## 4. Point important : correction du circuit associé à TRACK01

En vérifiant `game.c` (table `def.circuits`), `TRACK01` correspond en réalité
au circuit **« TERRAMAX »** (`CIRCUIT_TERRAMAX.settings[RACE_CLASS_VENOM].path
== "wipeout/track01/"`), et non « Altima VII » comme indiqué dans
[physique_vaisseau_audit.md](../../26-08-24-02/audit/physique_vaisseau_audit.md#4-constantes-non-dérivées-dun-facteur-déchelle-documenté)
(`CIRCUIT_ALTIMA_VII` pointe vers `wipeout/track02/`/`wipeout/track03/`).

Le facteur d'échelle ≈106,5 unités PSX/mètre documenté à cet endroit a été
calculé à partir de la longueur de lap réelle documentée pour Altima VII
(≈5500 m), donc potentiellement appliqué au mauvais circuit. À corriger ou
recalculer avec une longueur de référence pour Terramax si une source fiable
est trouvée.
