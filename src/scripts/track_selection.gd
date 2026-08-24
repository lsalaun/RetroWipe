extends Node

## Autoload: holds the track picked from the main menu so `main.tscn` knows
## which track scene to instantiate on launch.

const TRACKS: Array[Dictionary] = [
	{"name": "Track 12", "scene": "res://scenes/Track12.tscn"},
	{"name": "Track 01", "scene": "res://scenes/Track01.tscn"},
]

var selected_track_scene: PackedScene = null


func select_track(scene_path: String) -> void:
	selected_track_scene = load(scene_path)
