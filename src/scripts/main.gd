extends Node3D

const RaceFieldScript = preload("res://scripts/race_field.gd")

@export var default_track_scene: PackedScene
@export var ai_ship_scene: PackedScene


func _ready() -> void:
	var track_scene: PackedScene = default_track_scene
	if TrackSelection.selected_track_scene != null:
		track_scene = TrackSelection.selected_track_scene

	var track := track_scene.instantiate()
	track.name = "Track"
	add_child(track)
	move_child(track, 0)

	var center_line := track.get_node_or_null("CenterLine") as Path3D
	var spawn := track.get_node_or_null("ShipSpawn") as Marker3D

	_clear_placeholder_ai()
	var player := _find_player_ship()
	if player == null:
		return

	if RaceSetup.race_type == RaceSetup.RACE_TYPE_TIME_TRIAL:
		player.center_line = center_line
		RaceFieldScript.place_ship(player, spawn, RaceFieldScript.NUM_PILOTS - 1)
		if ShipSelection.selected_ship_scene != null:
			player.set_ship_model(ShipSelection.selected_ship_scene)
		return

	var player_pilot := RaceSetup.pilot_name
	if player_pilot == "":
		player_pilot = str(ShipSelection.SHIPS[0]["pilot"])
	var start_order := RaceFieldScript.build_start_order(player_pilot)
	var circuit := RaceFieldScript.circuit_settings_for(RaceFieldScript.track_display_name(), RaceSetup.race_class)
	var ai_index := 0

	for i in start_order.size():
		var entry: Dictionary = start_order[i]
		var inv_rank := (RaceFieldScript.NUM_PILOTS - 1) - i
		var is_player := str(entry.get("pilot", "")) == player_pilot
		var ship: WipeoutShip
		if is_player:
			ship = player
		else:
			ship = _spawn_ai_ship(ai_index)
			ai_index += 1
			if ship == null:
				continue
		ship.center_line = center_line
		RaceFieldScript.place_ship(ship, spawn, i)
		var mesh_path := str(entry.get("mesh", ""))
		if mesh_path != "":
			var mesh_scene := load(mesh_path) as PackedScene
			if mesh_scene != null:
				ship.set_ship_model(mesh_scene)
		if ship is WipeoutShipAI:
			var settings := RaceFieldScript.ai_settings_for(RaceSetup.race_class, inv_rank)
			(ship as WipeoutShipAI).configure_from_race(settings, circuit, inv_rank)


func _clear_placeholder_ai() -> void:
	for child in get_children():
		if child is WipeoutShipAI:
			child.queue_free()


func _find_player_ship() -> WipeoutShip:
	for child in get_children():
		if child is WipeoutShip and not (child is WipeoutShipAI):
			return child
	return null


func _spawn_ai_ship(index: int) -> WipeoutShipAI:
	if ai_ship_scene == null:
		return null
	var ship := ai_ship_scene.instantiate() as WipeoutShipAI
	if ship == null:
		return null
	ship.name = "ShipAI%d" % (index + 1)
	add_child(ship)
	return ship

