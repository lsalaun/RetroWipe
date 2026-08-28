extends Node

## Autoload: holds the ship picked from the ship selection menu so `main.tscn`
## knows which visual model to apply to the player's ship on launch.
## Ship model names/order match COMMON/ALLSH.PRM's object names (see
## tools/psx_track/convert_ships.py); pilot display names come from
## src/wipeout/game.c's def.pilots.

const SHIPS: Array[Dictionary] = [
	{"pilot": "Sofia De La Rente", "team": "Feisar", "mesh": "res://assets/ships/sophia/sophia.glb", "portrait": "res://assets/ui/sophi/sophi_00.png"},
	{"pilot": "Kel Solaar", "team": "Qirex", "mesh": "res://assets/ships/solaar/solaar.glb", "portrait": "res://assets/ui/solar/solar_00.png"},
	{"pilot": "Paul Jackson", "team": "Feisar", "mesh": "res://assets/ships/jacko/jacko.glb", "portrait": "res://assets/ui/paul/paul_00.png"},
	{"pilot": "Daniel Chang", "team": "AG Systems", "mesh": "res://assets/ships/chang/chang.glb", "portrait": "res://assets/ui/chang/chang_00.png"},
	{"pilot": "Arian Tetsuo", "team": "Qirex", "mesh": "res://assets/ships/arian/arian.glb", "portrait": "res://assets/ui/arian/arian_00.png"},
	{"pilot": "Arial Tetsuo", "team": "Auricom", "mesh": "res://assets/ships/arial/arial.glb", "portrait": "res://assets/ui/arial/arial_00.png"},
	{"pilot": "Anastasia Cherovoski", "team": "Auricom", "mesh": "res://assets/ships/anasta/anasta.glb", "portrait": "res://assets/ui/anast/anast_00.png"},
	{"pilot": "John Dekka", "team": "AG Systems", "mesh": "res://assets/ships/Dekka/Dekka.glb", "portrait": "res://assets/ui/dekka/dekka_00.png"},
]

var selected_ship_scene: PackedScene = null


func select_ship(mesh_path: String) -> void:
	selected_ship_scene = load(mesh_path)
