extends Node

## Autoload: holds the ship picked from the ship selection menu so `main.tscn`
## knows which visual model to apply to the player's ship on launch.
## Ship model names/order match COMMON/ALLSH.PRM's object names (see
## tools/psx_track/convert_ships.py); pilot display names come from
## src/wipeout/game.c's def.pilots.

const SHIPS: Array[Dictionary] = [
	{"pilot": "Sofia De La Rente", "team": "Feisar", "mesh": "res://assets/ships/sophia/sophia.glb"},
	{"pilot": "Kel Solaar", "team": "Qirex", "mesh": "res://assets/ships/solaar/solaar.glb"},
	{"pilot": "Paul Jackson", "team": "Feisar", "mesh": "res://assets/ships/jacko/jacko.glb"},
	{"pilot": "Daniel Chang", "team": "AG Systems", "mesh": "res://assets/ships/chang/chang.glb"},
	{"pilot": "Arian Tetsuo", "team": "Qirex", "mesh": "res://assets/ships/arian/arian.glb"},
	{"pilot": "Arial Tetsuo", "team": "Auricom", "mesh": "res://assets/ships/arial/arial.glb"},
	{"pilot": "Anastasia Cherovoski", "team": "Auricom", "mesh": "res://assets/ships/anasta/anasta.glb"},
	{"pilot": "John Dekka", "team": "AG Systems", "mesh": "res://assets/ships/Dekka/Dekka.glb"},
]

var selected_ship_scene: PackedScene = null


func select_ship(mesh_path: String) -> void:
	selected_ship_scene = load(mesh_path)
