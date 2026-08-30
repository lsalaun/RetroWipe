extends Node

## Autoload: holds the track picked from CircuitMenu so `main.tscn` knows
## which track scene to instantiate on launch. Names match the circuits
## src/wipeout/game.c's def.circuits associates with these PSX tracks
## (TRACK01 -> TERRAMAX venom, TRACK02 -> ALTIMA VII venom, TRACK03 ->
## ALTIMA VII rapier, TRACK04 -> KARBONIS V venom, TRACK05 -> KARBONIS V
## rapier, TRACK06 -> TERRAMAX rapier, TRACK07 -> KORODERA rapier,
## TRACK08 -> ARRIDOS IV venom, TRACK09 -> SILVERSTREAM venom,
## TRACK10 -> FIRESTAR venom, TRACK11 -> ARRIDOS IV rapier,
## TRACK12 -> KORODERA venom, TRACK13 -> SILVERSTREAM rapier,
## TRACK14 -> FIRESTAR rapier).
## Optional `circuit` is the def.circuits key used by RaceField when `name`
## is a class-specific label.
## `start_line` is game.c's circuit_settings_t.start_line_pos, i.e. the TRACK.TRS
## section index of the start/finish line. Since the exported centerline JSON has
## one curve point per section, it doubles as the curve point index of the line
## (see tools/psx_track/circuit_catalog.py, which also derives ShipSpawn from it
## at start_line - 15).

const TRACKS: Array[Dictionary] = [
	{"name": "TERRAMAX", "scene": "res://scenes/Track01.tscn", "start_line": 27, "loading": "res://assets/ui/nload01.png"},
	{"name": "ALTIMA VII", "scene": "res://scenes/Track02.tscn", "start_line": 27, "loading": "res://assets/ui/nload02.png"},
	{"name": "ALTIMA VII RAPIER", "scene": "res://scenes/Track03.tscn", "circuit": "ALTIMA VII", "start_line": 27, "loading": "res://assets/ui/nload03.png"},
	{"name": "KARBONIS V", "scene": "res://scenes/Track04.tscn", "start_line": 16, "loading": "res://assets/ui/nload04.png"},
	{"name": "KARBONIS V RAPIER", "scene": "res://scenes/Track05.tscn", "circuit": "KARBONIS V", "start_line": 16, "loading": "res://assets/ui/nload05.png"},
	{"name": "TERRAMAX RAPIER", "scene": "res://scenes/Track06.tscn", "circuit": "TERRAMAX", "start_line": 27, "loading": "res://assets/ui/nload06.png"},
	{"name": "KORODERA RAPIER", "scene": "res://scenes/Track07.tscn", "circuit": "KORODERA", "start_line": 16, "loading": "res://assets/ui/nload07.png"},
	{"name": "ARRIDOS IV", "scene": "res://scenes/Track08.tscn", "start_line": 16, "loading": "res://assets/ui/nload08.png"},
	{"name": "SILVERSTREAM", "scene": "res://scenes/Track09.tscn", "start_line": 16, "loading": "res://assets/ui/nload09.png"},
	{"name": "FIRESTAR", "scene": "res://scenes/Track10.tscn", "start_line": 27, "loading": "res://assets/ui/nload10.png"},
	{"name": "ARRIDOS IV RAPIER", "scene": "res://scenes/Track11.tscn", "circuit": "ARRIDOS IV", "start_line": 16, "loading": "res://assets/ui/nload11.png"},
	{"name": "KORODERA", "scene": "res://scenes/Track12.tscn", "start_line": 16, "loading": "res://assets/ui/nload12.png"},
	{"name": "SILVERSTREAM RAPIER", "scene": "res://scenes/Track13.tscn", "circuit": "SILVERSTREAM", "start_line": 16, "loading": "res://assets/ui/nload13.png"},
	{"name": "FIRESTAR RAPIER", "scene": "res://scenes/Track14.tscn", "circuit": "FIRESTAR", "start_line": 27, "loading": "res://assets/ui/nload14.png"},
]

## circuit_catalog.py SPAWN_SECTION_OFFSET: ships_init() lines the grid up 15
## sections before start_line_pos, which is where each track's ShipSpawn sits.
const SPAWN_SECTION_OFFSET := 15

## RaceSetup.RACE_CLASS_RAPIER, duplicated because RaceSetup is registered after
## this autoload and referencing it here would fail to compile at startup.
const RAPIER_CLASS := 1

const LOADING_SCENE := "res://scenes/LoadingScreen.tscn"
const RACE_SCENE := "res://scenes/main.tscn"

var selected_track_scene: PackedScene = null


func select_track(scene_path: String) -> void:
	selected_track_scene = load(scene_path)


func loading_path_for_scene(scene_path: String) -> String:
	for track in TRACKS:
		if track["scene"] == scene_path:
			return str(track.get("loading", ""))
	return ""


func selected_loading_path() -> String:
	if selected_track_scene == null:
		return str(TRACKS[0].get("loading", ""))
	return loading_path_for_scene(selected_track_scene.resource_path)


func start_line_section_for(scene_path: String) -> int:
	for track in TRACKS:
		if track["scene"] == scene_path:
			return int(track.get("start_line", 27))
	return 27


func selected_start_line_section() -> int:
	if selected_track_scene == null:
		return int(TRACKS[0].get("start_line", 27))
	return start_line_section_for(selected_track_scene.resource_path)


func start_race(tree: SceneTree) -> void:
	tree.change_scene_to_file(LOADING_SCENE)


## RaceSetup.start_attract_mode()'s track pick: any TRACKS entry whose Venom/
## Rapier suffix matches `race_class_value`.
func random_track_scene_for(race_class_value: int) -> PackedScene:
	var want_rapier := race_class_value == RAPIER_CLASS
	var candidates: Array[Dictionary] = []
	for track in TRACKS:
		if str(track["name"]).ends_with(" RAPIER") == want_rapier:
			candidates.append(track)
	if candidates.is_empty():
		candidates = TRACKS
	var pick: Dictionary = candidates[randi() % candidates.size()]
	return load(str(pick["scene"])) as PackedScene


## def.circuits order for the seven WIPEOUT circuits (game.h, CIRCUIT_ALTIMA_VII
## .. CIRCUIT_FIRESTAR). main_menu.c's page_circuit_init lists them in this
## order, and track.cmp's preview images are indexed by the same enum.
const CIRCUIT_ORDER: Array[String] = [
	"ALTIMA VII",
	"KARBONIS V",
	"TERRAMAX",
	"KORODERA",
	"ARRIDOS IV",
	"SILVERSTREAM",
	"FIRESTAR",
]


## track.cmp entry `circuit_index`, exported as assets/ui/track/track_NN.png:
## the 128x74 preview main_menu.c's page_circuit_draw shows for the highlighted
## circuit.
func circuit_image_path(circuit_index: int) -> String:
	return "res://assets/ui/track/track_%02d.png" % circuit_index


## TRACKS carries one entry per PSX track file, i.e. a venom and a rapier
## variant of each circuit, the rapier ones naming their circuit under
## `circuit`. The original menu instead lists each circuit once and takes the
## variant from g.race_class, which is what this resolves here. `race_class` is
## a RaceSetup.RACE_CLASS_* value. Returns "" if the circuit has no track for
## that class.
func scene_for_circuit(circuit: String, race_class: int) -> String:
	var want_rapier := race_class == RAPIER_CLASS
	for track in TRACKS:
		var track_name := str(track["name"])
		if track_name.ends_with(" RAPIER") != want_rapier:
			continue
		if str(track.get("circuit", track_name)) == circuit:
			return str(track["scene"])
	return ""
