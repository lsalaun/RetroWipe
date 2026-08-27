extends Node
class_name RaceField

## Race-level AI field: 8-ship grid, opponent models, DPA settings and live
## ranking. Mirrors ships_init() / ships_update() in src/wipeout/ship.c without
## cloning the PSX section-based start stagger.

const NUM_PILOTS := 8
const NUM_AI_OPPONENTS := 7

## Staggered 2-column grid in ShipSpawn local space (right, up, behind).
## Index 0 is pole (front); the player is always last, matching ships_init().
const GRID_OFFSETS: Array[Vector3] = [
	Vector3(-3.0, 0.0, 0.0),
	Vector3(3.0, 0.0, 2.0),
	Vector3(-3.0, 0.0, 4.0),
	Vector3(3.0, 0.0, 6.0),
	Vector3(-3.0, 0.0, 8.0),
	Vector3(3.0, 0.0, 10.0),
	Vector3(-3.0, 0.0, 12.0),
	Vector3(3.0, 0.0, 14.0),
]

## Per-class opponent tables from game.c def.ai_settings. Index 0 is the
## strongest (front of grid / inv_start_rank-1 == 0).
const AI_SETTINGS: Dictionary = {
	0: [
		{"thrust_max": 2550.0, "thrust_magnitude": 44.0, "fight_back": true},
		{"thrust_max": 2600.0, "thrust_magnitude": 45.0, "fight_back": true},
		{"thrust_max": 2630.0, "thrust_magnitude": 45.0, "fight_back": true},
		{"thrust_max": 2660.0, "thrust_magnitude": 46.0, "fight_back": true},
		{"thrust_max": 2700.0, "thrust_magnitude": 47.0, "fight_back": true},
		{"thrust_max": 2720.0, "thrust_magnitude": 48.0, "fight_back": true},
		{"thrust_max": 2750.0, "thrust_magnitude": 49.0, "fight_back": true},
	],
	1: [
		{"thrust_max": 3750.0, "thrust_magnitude": 50.0, "fight_back": true},
		{"thrust_max": 3780.0, "thrust_magnitude": 53.0, "fight_back": true},
		{"thrust_max": 3800.0, "thrust_magnitude": 55.0, "fight_back": true},
		{"thrust_max": 3850.0, "thrust_magnitude": 57.0, "fight_back": true},
		{"thrust_max": 3900.0, "thrust_magnitude": 60.0, "fight_back": true},
		{"thrust_max": 3950.0, "thrust_magnitude": 62.0, "fight_back": true},
		{"thrust_max": 4000.0, "thrust_magnitude": 65.0, "fight_back": true},
	],
}

const CIRCUIT_SETTINGS: Dictionary = {
	"TERRAMAX": {
		0: {"behind_speed": 350.0, "spread_base": 60.0, "spread_factor": 11.0},
		1: {"behind_speed": 500.0, "spread_base": 10.0, "spread_factor": 8.0},
	},
	"ALTIMA VII": {
		0: {"behind_speed": 300.0, "spread_base": 80.0, "spread_factor": 20.0},
		1: {"behind_speed": 500.0, "spread_base": 80.0, "spread_factor": 11.0},
	},
	"KORODERA": {
		0: {"behind_speed": 450.0, "spread_base": 40.0, "spread_factor": 11.0},
		1: {"behind_speed": 500.0, "spread_base": 30.0, "spread_factor": 11.0},
	},
}


static func circuit_settings_for(track_name: String, race_class: int) -> Dictionary:
	var by_class: Dictionary = CIRCUIT_SETTINGS.get(track_name, CIRCUIT_SETTINGS["TERRAMAX"])
	return by_class.get(race_class, by_class[0])


static func ai_settings_for(race_class: int, inv_start_rank: int) -> Dictionary:
	var table: Array = AI_SETTINGS.get(race_class, AI_SETTINGS[0])
	var index := clampi(inv_start_rank - 1, 0, table.size() - 1)
	return table[index]


static func track_display_name() -> String:
	if TrackSelection.selected_track_scene == null:
		return "KORODERA"
	var path := TrackSelection.selected_track_scene.resource_path
	for track in TrackSelection.TRACKS:
		if track["scene"] == path:
			return str(track.get("circuit", track["name"]))
	return "KORODERA"


static func build_start_order(player_pilot: String) -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	for ship in ShipSelection.SHIPS:
		roster.append(ship)
	roster.shuffle()
	for i in roster.size():
		if str(roster[i].get("pilot", "")) == player_pilot:
			var player_entry: Dictionary = roster[i]
			roster.remove_at(i)
			roster.append(player_entry)
			break
	return roster


static func place_ship(ship: WipeoutShip, spawn: Marker3D, grid_index: int) -> void:
	if spawn == null or grid_index < 0 or grid_index >= GRID_OFFSETS.size():
		return
	ship.respawn_at(spawn.global_transform.translated_local(GRID_OFFSETS[grid_index]))


func _physics_process(_delta: float) -> void:
	_update_ranks()


func _update_ranks() -> void:
	var ships: Array = get_tree().get_nodes_in_group(&"ships")
	ships.sort_custom(_compare_race_progress)
	for i in ships.size():
		var ship := ships[i] as WipeoutShip
		if ship != null:
			ship.position_rank = i + 1


func _compare_race_progress(a: Variant, b: Variant) -> bool:
	var ship_a := a as WipeoutShip
	var ship_b := b as WipeoutShip
	if ship_a == null or ship_b == null:
		return false
	return ship_a.race_progress > ship_b.race_progress
