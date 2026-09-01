# Ciel — dôme SKY.PRM planté dans le décor

**Date :** 2026-09-01
**Statut :** Terminé
**Portée :** Faire du dôme de ciel un vrai fond de scène (recentré sur la caméra, dessiné derrière tout) au lieu d'un objet statique posé à l'origine du circuit

---

## Résumé

Sur les circuits, le ciel apparaissait comme une coupole bleue à facettes
enfoncée dans les montagnes, et disparaissait du champ de vision dès qu'on
s'éloignait du centre du circuit.

Cause : le nœud `Sky` des `TrackNN.tscn` n'était qu'une instance brute du GLB,
posée à l'origine du circuit et sans script. Dans l'original, `SKY.PRM` n'est
jamais un objet du monde — `scene.c` le recentre sur la caméra à chaque frame et
le dessine en premier, écriture de profondeur coupée.

---

## Symptôme

- Circuit : constaté sur Track01 (TERRAMAX), présent sur les 14 scènes
- Comportement : dôme bleu texturé nuages visiblement intersecté par le relief,
  et absent du champ de vision sur la moitié éloignée du tracé
- Effet secondaire : le dôme projetait une ombre du `Sun` (`DirectionalLight3D`)
  sur l'ensemble du circuit

---

## Investigation

### Ce que fait l'original

`src/wipeout/scene.c`, `scene_draw()` :

```c
// Sky
render_set_depth_write(false);
mat4_set_translation(&sky_object->mat, vec3_add(camera->position, sky_offset));
object_draw(sky_object, &sky_object->mat);
render_set_depth_write(true);
```

Trois propriétés, toutes perdues à l'import :

1. le dôme suit la caméra (translation seule, pas de rotation) ;
2. il est dessiné **en premier**, donc tout le reste peint par-dessus ;
3. il n'écrit **aucune profondeur**, donc il n'occulte jamais rien — y compris
   la géométrie située plus loin que le rayon du dôme.

`sky_offset` vient du `sky_y_offset` par circuit de `game.c` (`def.circuits`).

### Échelles mesurées

AABB du dôme importé, relevée en headless :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src `
  -s res://tools/inspect_scene.gd -- res://assets/tracks/Track_01/Track_01_sky.glb
```

| Source | Valeur |
| --- | --- |
| AABB `Track_01_sky` | position `(-182.96, -65.20, -183.03)`, taille `(366.10, 242.54, 366.08)` |
| Rayon max depuis l'origine | ~314 m |
| Étendue du tracé Track01 | > 1200 m de l'origine (ex. point de ligne centrale `(823.6, 1.2, 1183.8)`) |
| `far` de la caméra (`WipeoutShip.tscn`) | 400 m |

Un dôme de 314 m de rayon posé à l'origine ne peut donc pas couvrir un circuit
de plus de 1200 m d'envergure : c'est exactement l'artefact observé.

### Pourquoi un shader et pas seulement un déplacement

Recentrer le dôme sur la caméra ne suffit pas : à 180-300 m, tout relief situé
entre le dôme et le plan `far` (400 m) le traverserait. Il faut aussi reproduire
le « dessiné en premier, sans écriture Z ».

Godot n'expose aucun moyen de forcer un maillage opaque en tête de la liste de
rendu (`render_priority` ne trie que les matériaux transparents). Deux pistes
écartées :

- **Agrandir le dôme jusqu'au plan `far`** : il faudrait le rendre sphérique
  (le maillage est un caisson, ses faces les plus proches resteraient à ~220 m)
  et remonter le `far` de la caméra, ce qui change la distance d'affichage du
  reste du circuit.
- **`no_depth_test` sur le matériau** : le résultat dépendrait alors de l'ordre
  de dessin, non garanti pour les objets opaques.

Retenu : garder le test de profondeur, n'écrire aucune profondeur, et aplatir la
profondeur clip-space du dôme sur le plan lointain. Le résultat est identique à
celui de l'original et il est **indépendant de l'ordre de rendu** — rien ne peut
plus passer devant le ciel, ni être masqué par lui.

---

## Modifications

### 1. `src/shaders/track_sky.gdshader` (nouveau)

```glsl
shader_type spatial;
render_mode unshaded, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.w * 1e-5;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * COLOR.rgb;
}
```

- `unshaded` : l'original n'a aucun éclairage dynamique, tout est cuit dans les
  couleurs par sommet du PRM.
- `depth_draw_never` : équivalent direct de `render_set_depth_write(false)`.
- `POSITION.z = POSITION.w * 1e-5` : Godot 4 utilise un tampon de profondeur en
  Z inversé (NDC z = 1.0 au plan proche, 0.0 au plan lointain). On se place
  juste avant 0.0, pour rester derrière toute la scène tout en passant le test
  contre un tampon effacé à la valeur du plan lointain.
- `COLOR` reprend le `COLOR_0` du glTF, que le `StandardMaterial3D` importé
  consommait via `vertex_color_use_as_albedo` (vérifié : `true`), et
  `filter_linear_mipmap` reprend son `texture_filter` (`LINEAR_WITH_MIPMAPS`).

### 2. `src/scripts/track_sky.gd` (nouveau)

Porté sur le nœud `Sky` de chaque circuit :

- `_process()` : `global_position = camera.global_position + Vector3(0, sky_y_offset, 0)`.
  La caméra est relue à chaque frame plutôt que mise en cache, la course
  basculant entre le `CameraRig` du joueur et `AttractCamera` sans recharger le
  circuit.
- `process_priority = 1000` : `AttractCamera` se déplace dans `_process()`, le
  dôme doit se recentrer après elle, sinon le fond « nage » d'une frame.
- `cast_shadow = SHADOW_CASTING_SETTING_OFF` sur les `MeshInstance3D` : supprime
  l'ombre du dôme sur le circuit.
- Remplace le matériau importé par un `ShaderMaterial`, en reprenant son
  `albedo_texture`.
- `@export var sky_y_offset: float` : hauteur du dôme au-dessus de la caméra, en
  mètres.

Garde-fou headless : le renderer factice n'a pas de compilateur de shaders et
journalise `Parameter "material" is null` à chaque `set_surface_override_material()`
recevant un `ShaderMaterial`. Le swap de matériaux est donc sauté quand
`DisplayServer.get_name() == "headless"` — rien n'y est dessiné de toute façon.
Le recentrage, lui, continue de tourner.

### 3. `sky_y_offset` par circuit

Valeur C de `game.c` (unités PSX brutes, Y vers le bas) → mètres Godot : la
valeur est niée comme toute position importée, puis divisée par les 106.5
unités/mètre de l'importeur.

| Scène | Dossier PSX | `sky_y_offset` C | `sky_y_offset` Godot (m) |
| --- | --- | --- | --- |
| Track01 | TRACK01 | -820 | 7.6995 |
| Track02 | TRACK02 | -2520 | 23.662 |
| Track03 | TRACK03 | -1930 | 18.1221 |
| Track04 | TRACK04 | -5000 | 46.9484 |
| Track05 | TRACK05 | -5000 | 46.9484 |
| Track06 | TRACK06 | 0 | 0.0 |
| Track07 | TRACK07 | -2260 | 21.2207 |
| Track08 | TRACK08 | -40 | 0.3756 |
| Track09 | TRACK09 | -2700 | 25.3521 |
| Track10 | TRACK10 | 0 | 0.0 |
| Track11 | TRACK11 | -240 | 2.2535 |
| Track12 | TRACK12 | -2120 | 19.9061 |
| Track13 | TRACK13 | -2700 | 25.3521 |
| Track14 | TRACK14 | 0 | 0.0 |

### 4. Les 14 `TrackNN.tscn`

```diff
 [ext_resource type="Script" path="res://scripts/track_gameplay_zones.gd" id="6_script"]
+[ext_resource type="Script" path="res://scripts/track_sky.gd" id="7_sky_script"]
 ...
 [node name="Sky" parent="." instance=ExtResource("5_sky")]
+script = ExtResource("7_sky_script")
+sky_y_offset = 7.6995
```

La propagation vers le pipeline d'import est traitée dans
`import-track-sky-offset.md`.

---

## Validation

### Rendu

Six points de vue répartis le long de la ligne centrale de Track01 (caméra
`fov = 82`, `near = 0.05`, `far = 400`, alignée sur celle de `WipeoutShip.tscn`),
plus un boot direct de `scenes/main.tscn` :

- ciel correctement occulté par les collines, par le tunnel et par la tribune ;
- ciel présent et cohérent à `(823.6, 1.2, 1183.8)`, soit ~1200 m de l'origine,
  là où l'ancien dôme statique n'apparaissait tout simplement plus ;
- l'emplacement du rapport de bug (rocher sombre avec entrée de tunnel) est
  propre : plus aucune facette bleue dans le relief ;
- plus d'ombre portée du dôme.

### Non-régression

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src -s res://tools/validate_track_loading.gd
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src -s res://tools/validate_attract_mode.gd
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src -s res://tools/validate_race_logic.gd
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path src -s res://tools/validate_time_trial.gd
```

Les quatre rapportent `OK`, sans bruit supplémentaire par rapport à la sortie
d'avant le correctif (comparaison faite en remisant les `TrackNN.tscn`).

---

## Non modifié

- Le maillage `Track_NN_sky.glb` et sa texture : aucun ré-export, seul le rendu
  change.
- Le `ProceduralSkyMaterial` du `WorldEnvironment` de `main.tscn` : il ne sert
  plus que sous le bord bas du dôme (celui-ci s'arrête à -65 m sous son centre).
  Il pourrait apparaître dans une descente très plongeante — laissé tel quel,
  arbitrage à faire.
- Le `far` de la caméra (400 m), la géométrie de piste et le décor.
- Le mode de culling : le `cull_back` du matériau importé est conservé.

---

## Fichiers modifiés

- `src/shaders/track_sky.gdshader` (nouveau)
- `src/scripts/track_sky.gd` (nouveau)
- `src/scenes/Track01.tscn` … `src/scenes/Track14.tscn`
- `docs/.transactional/26-09-01-01/tickets/ciel-dome-recentre-camera.md`
