extends Node

## Autoload: holds the track picked from CircuitMenu so `main.tscn` knows
## which track scene to instantiate on launch. Names match the circuits
## src/wipeout/game.c's def.circuits associates with these PSX tracks
## (TRACK01 -> TERRAMAX, TRACK12 -> KORODERA, venom class paths).

const TRACKS: Array[Dictionary] = [
	{"name": "TERRAMAX", "scene": "res://scenes/Track01.tscn"},
	{"name": "KORODERA", "scene": "res://scenes/Track12.tscn"},
]

var selected_track_scene: PackedScene = null


func select_track(scene_path: String) -> void:
	selected_track_scene = load(scene_path)
