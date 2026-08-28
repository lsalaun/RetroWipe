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

const TRACKS: Array[Dictionary] = [
	{"name": "TERRAMAX", "scene": "res://scenes/Track01.tscn", "loading": "res://assets/ui/nload01.png"},
	{"name": "ALTIMA VII", "scene": "res://scenes/Track02.tscn", "loading": "res://assets/ui/nload02.png"},
	{"name": "ALTIMA VII RAPIER", "scene": "res://scenes/Track03.tscn", "circuit": "ALTIMA VII", "loading": "res://assets/ui/nload03.png"},
	{"name": "KARBONIS V", "scene": "res://scenes/Track04.tscn", "loading": "res://assets/ui/nload04.png"},
	{"name": "KARBONIS V RAPIER", "scene": "res://scenes/Track05.tscn", "circuit": "KARBONIS V", "loading": "res://assets/ui/nload05.png"},
	{"name": "TERRAMAX RAPIER", "scene": "res://scenes/Track06.tscn", "circuit": "TERRAMAX", "loading": "res://assets/ui/nload06.png"},
	{"name": "KORODERA RAPIER", "scene": "res://scenes/Track07.tscn", "circuit": "KORODERA", "loading": "res://assets/ui/nload07.png"},
	{"name": "ARRIDOS IV", "scene": "res://scenes/Track08.tscn", "loading": "res://assets/ui/nload08.png"},
	{"name": "SILVERSTREAM", "scene": "res://scenes/Track09.tscn", "loading": "res://assets/ui/nload09.png"},
	{"name": "FIRESTAR", "scene": "res://scenes/Track10.tscn", "loading": "res://assets/ui/nload10.png"},
	{"name": "ARRIDOS IV RAPIER", "scene": "res://scenes/Track11.tscn", "circuit": "ARRIDOS IV", "loading": "res://assets/ui/nload11.png"},
	{"name": "KORODERA", "scene": "res://scenes/Track12.tscn", "loading": "res://assets/ui/nload12.png"},
	{"name": "SILVERSTREAM RAPIER", "scene": "res://scenes/Track13.tscn", "circuit": "SILVERSTREAM", "loading": "res://assets/ui/nload13.png"},
	{"name": "FIRESTAR RAPIER", "scene": "res://scenes/Track14.tscn", "circuit": "FIRESTAR", "loading": "res://assets/ui/nload14.png"},
]

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


func start_race(tree: SceneTree) -> void:
	tree.change_scene_to_file(LOADING_SCENE)
