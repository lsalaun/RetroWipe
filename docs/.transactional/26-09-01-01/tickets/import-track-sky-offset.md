# Pipeline d'import — propagation du script de ciel et du `sky_y_offset`

**Date :** 2026-09-01
**Statut :** Terminé
**Portée :** Faire en sorte qu'un ré-import de circuit régénère une `TrackNN.tscn` qui garde le correctif de ciel, au lieu d'écraser le nœud `Sky` par une instance nue

---

## Résumé

Le correctif décrit dans `ciel-dome-recentre-camera.md` a été appliqué
directement aux 14 `TrackNN.tscn`. Or ces scènes sont générées par
`import_track.py --write-scene` : un ré-import (ou l'import d'un nouveau
circuit) aurait réécrit un nœud `Sky` sans script, réintroduisant l'artefact
silencieusement.

Le gabarit de scène de l'importeur et le catalogue de circuits sont donc mis à
jour pour porter la même information que les scènes corrigées à la main.

---

## Investigation

`sky_y_offset` est une donnée par *réglage de circuit* dans `src/wipeout/game.c`
(`def.circuits[...].settings[RACE_CLASS_*]`), au même titre que
`start_line_pos` que `circuit_catalog.py` recopie déjà. Le catalogue étant
indexé par dossier PSX (`TRACK01` … `TRACK15`), chaque entrée correspond à
exactement un couple circuit/classe, donc à exactement un `sky_y_offset` : la
donnée s'y range sans ambiguïté.

`TRACK15` n'est pas dans `def.circuits` (reliquat d'outillage, `TRACK.INF`
`outName = trak1`) — il reçoit le 0 neutre, comme pour les autres champs.

---

## Modifications

### 1. `tools/psx_track/circuit_catalog.py`

- Champ `"sky_y_offset"` ajouté aux 15 entrées de `CIRCUITS`, avec la valeur C
  brute (unités PSX, Y vers le bas) — cohérent avec `start_line_pos`, lui aussi
  stocké tel quel et converti au moment de l'usage.
- Nouvelle fonction :

```python
def sky_y_offset_meters(track_folder: str, units_per_meter: float) -> float:
    """Height of the SKY.PRM dome above the camera, in Godot metres.

    The C `sky_y_offset` is in raw PSX units on a downward Y axis, so it is
    negated like every other imported position before being scaled.
    """
    info = CIRCUITS.get(folder_key(track_folder), {})
    return round(-int(info.get("sky_y_offset", 0)) / units_per_meter, 4)
```

  Elle prend `units_per_meter` en paramètre plutôt que la constante, pour rester
  correcte quand l'import tourne avec `--units-per-meter`.

- L'en-tête du module documente le nouveau champ et l'axe Y descendant.

### 2. `tools/psx_track/import_track.py`

- `write_track_scene()` prend un paramètre `sky_y_offset: float`.
- Le gabarit de scène gagne la ressource et les deux lignes de nœud :

```diff
 [ext_resource type="Script" path="res://scripts/track_gameplay_zones.gd" id="6_script"]
+[ext_resource type="Script" path="res://scripts/track_sky.gd" id="7_sky_script"]
 ...
 [node name="Sky" parent="." instance=ExtResource("5_sky")]
+script = ExtResource("7_sky_script")
+sky_y_offset = {sky_y_offset}
```

- L'appel passe la valeur convertie :

```diff
-            write_track_scene(nn, scene_path, spawn_literal)
+            write_track_scene(nn, scene_path, spawn_literal, sky_y_offset_meters(folder, args.units_per_meter))
```

`folder` est déjà le `TRACKNN` utilisé pour `spawn_section_index()`, donc la
même clé sert aux deux lookups.

---

## Validation

Le gabarit produit exactement ce qui a été écrit à la main dans les 14 scènes :
même id de ressource (`7_sky_script`), même ordre de lignes, même valeur
d'offset. Un `--write-scene --overwrite-scene` régénère donc une scène
équivalente à la version corrigée.

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src --import
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src -s res://tools/validate_track_loading.gd
```

Import sans erreur, `validate_track_loading: OK` (les 14 scènes se chargent et
restent appairées à leur écran de chargement).

Non exécuté : un vrai `import_track.py` de bout en bout, qui demande Blender et
les données PSX d'origine. Le gabarit n'est pour l'instant validé que par
comparaison avec les scènes corrigées.

---

## Non modifié

- Les autres champs du catalogue (`start_line_pos`, `race_class`, `circuit`,
  `in_game`) et `spawn_section_index()`.
- `DEFAULT_UNITS_PER_METER` (106.5) et les converters géométriques.
- Les circuits Wipeout 2097 / Wipeout 64 de `def.circuits` : hors périmètre de
  `circuit_catalog.py`, qui ne couvre que les dossiers PSX du premier jeu.

---

## Fichiers modifiés

- `tools/psx_track/circuit_catalog.py`
- `tools/psx_track/import_track.py`
- `docs/.transactional/26-09-01-01/tickets/import-track-sky-offset.md`
