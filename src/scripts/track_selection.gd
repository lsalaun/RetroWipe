extends Node

## Autoload: holds the track picked from CircuitMenu so `main.tscn` knows
## which track scene to instantiate on launch. Names match the circuits
## src/wipeout/game.c's def.circuits associates with these PSX tracks
## (TRACK01 -> TERRAMAX venom, TRACK02 -> ALTIMA VII venom, TRACK03 ->
## ALTIMA VII rapier, TRACK04 -> KARBONIS V venom, TRACK05 -> KARBONIS V
## rapier, TRACK06 -> TERRAMAX rapier, TRACK07 -> KORODERA rapier,
## TRACK12 -> KORODERA venom). Optional `circuit` is the def.circuits key
## used by RaceField when `name` is a class-specific label.

const TRACKS: Array[Dictionary] = [
	{"name": "TERRAMAX", "scene": "res://scenes/Track01.tscn"},
	{"name": "ALTIMA VII", "scene": "res://scenes/Track02.tscn"},
	{"name": "ALTIMA VII RAPIER", "scene": "res://scenes/Track03.tscn", "circuit": "ALTIMA VII"},
	{"name": "KARBONIS V", "scene": "res://scenes/Track04.tscn"},
	{"name": "KARBONIS V RAPIER", "scene": "res://scenes/Track05.tscn", "circuit": "KARBONIS V"},
	{"name": "TERRAMAX RAPIER", "scene": "res://scenes/Track06.tscn", "circuit": "TERRAMAX"},
	{"name": "KORODERA RAPIER", "scene": "res://scenes/Track07.tscn", "circuit": "KORODERA"},
	{"name": "KORODERA", "scene": "res://scenes/Track12.tscn"},
]

var selected_track_scene: PackedScene = null


func select_track(scene_path: String) -> void:
	selected_track_scene = load(scene_path)
