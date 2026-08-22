# Piste 01 — spline centrale IA : diagnostic et intégration

## Contexte

Une piste 3D a été ajoutée : mesh (`track_12_mesh.glb`) et spline centrale
destinée à guider les vaisseaux IA (`track_12_curve.glb`, exportée depuis
`track_12_curve.blend`). À l'import dans Godot, la spline apparaissait vide.

## Diagnostic

Inspection directe du `.blend` en mode headless :

```powershell
blender --background "track_12_curve.blend" --python "inspect_curve.py"
```

Résultat : la courbe existe bien (`BézierCurve`, spline `BEZIER`, 21 points,
`use_cyclic_u=True`), mais `bevel_depth=0.0` et `extrude=0.0` (courbe filaire
sans épaisseur). **L'exportateur glTF de Blender n'exporte pas les objets
`CURVE`** — il ne les convertit jamais automatiquement en mesh, donc ils
ressortent comme un nœud vide (0 mesh, 0 accessor) à l'import, quelle que
soit l'épaisseur.

## Solution : export direct par script Blender, sans passer par glTF

Nouveau script [godot/tools/blender/export_track_curve.py](../../../tools/blender/export_track_curve.py) :

- Tourne en headless : `blender --background <track.blend> --python export_track_curve.py -- <output.json> [resolution] [object_name]`
- Échantillonne la spline Bezier directement via `mathutils.geometry.interpolate_bezier` (segment par segment, respecte `use_cyclic_u`)
- Convertit les coordonnées Blender (Z-up) vers Godot (Y-up) : `(x, y, z) -> (x, z, -y)`
- Écrit un JSON ordonné : `{"points": [[x,y,z], ...], "closed": bool, "source_object": str}`

Exécuté sur `track_12_curve.blend` → **316 points** générés (résolution 16
par segment), courbe fermée détectée. Fichier écrit dans
`godot/src/assets/tracks/Track_01/track_12_curve.json`.

## Intégration Godot

### `track_center_line.gd`
Réécrit pour charger en priorité un fichier JSON (`source_json`) et
construire un vrai `Curve3D` (avec `.closed = true`, propriété native
disponible en Godot 4.6). L'ancien fallback sur `source_scene` (scan d'un
`Path3D` dans la scène glTF) est conservé en secours, puis un placeholder
rectiligne en dernier recours — le tout avec des avertissements explicites
pour ne jamais échouer silencieusement.

### Repositionnement du spawn
Le point de départ réel de la courbe (premier point échantillonné) a servi à
recalculer :
- La hauteur de surface réelle de la piste à cet endroit (raycast contre la
  collision du mesh importé)
- L'orientation du vaisseau, alignée sur la tangente de la courbe à ce point
  (`Basis.looking_at`)

Répercuté dans :
- [Track01.tscn](../../../scenes/Track01.tscn) (`ShipSpawn`)
- [main.tscn](../../../scenes/main.tscn) (`Ship`, `ShipAI1`, `ShipAI2`)

## Vérification

Exécution réelle de `main.tscn` pendant 2s en headless
(`await physics_frame` × 120, puis `quit()` propre pour ne pas perdre les
logs bufferisés) :

- `curve_points=316 closed=true` — la vraie spline est chargée, plus aucun
  avertissement de placeholder
- Le vaisseau joueur et les deux vaisseaux IA (`ShipAI1`/`ShipAI2`) restent
  posés sur la piste réelle et bougent de façon cohérente le long de la
  courbe

Validation projet complète (`godot --headless --path godot --quit`) : aucune
erreur.

## Pour les prochaines pistes

Relancer `export_track_curve.py` sur chaque nouveau `.blend` de courbe pour
régénérer son JSON — plus besoin de retoucher le pipeline glTF ni de
convertir manuellement la courbe en mesh dans Blender.
