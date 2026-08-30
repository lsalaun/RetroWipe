extends Node3D

const RaceFieldScript = preload("res://scripts/race_field.gd")

@export var default_track_scene: PackedScene
@export var ai_ship_scene: PackedScene


func _ready() -> void:
	# weapons_init(): the manager is an autoload, so anything still in flight
	# from a previous race has to be dropped here.
	var weapon_manager := WipeoutWeaponManager.instance(get_tree())
	if weapon_manager != null:
		weapon_manager.clear_all_weapons()

	var track_scene: PackedScene = default_track_scene
	if TrackSelection.selected_track_scene != null:
		track_scene = TrackSelection.selected_track_scene

	var track := track_scene.instantiate()
	track.name = "Track"
	add_child(track)
	move_child(track, 0)

	var center_line := track.get_node_or_null("CenterLine") as Path3D
	var spawn := track.get_node_or_null("ShipSpawn") as Marker3D
	var start_line_offset := _start_line_offset(center_line, track_scene)
	var spawn_offset := _spawn_offset(center_line, track_scene)

	_clear_placeholder_ai()
	var player := _find_player_ship()
	if player == null:
		return

	if RaceSetup.race_type == RaceSetup.RACE_TYPE_TIME_TRIAL:
		player.center_line = center_line
		player.start_line_offset = start_line_offset
		RaceFieldScript.place_ship(player, spawn, center_line, spawn_offset, RaceFieldScript.NUM_PILOTS - 1)
		if ShipSelection.selected_ship_scene != null:
			player.set_ship_model(ShipSelection.selected_ship_scene)
		player.pilot_name = RaceSetup.pilot_name
		_apply_ship_attributes(player, RaceSetup.pilot_name)
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
		ship.start_line_offset = start_line_offset
		RaceFieldScript.place_ship(ship, spawn, center_line, spawn_offset, i)
		var mesh_path := str(entry.get("mesh", ""))
		if mesh_path != "":
			var mesh_scene := load(mesh_path) as PackedScene
			if mesh_scene != null:
				ship.set_ship_model(mesh_scene)
		ship.pilot_name = str(entry.get("pilot", ""))
		_apply_ship_attributes(ship, str(entry.get("pilot", "")), str(entry.get("team", "")))
		if ship is WipeoutShipAI:
			var settings := RaceFieldScript.ai_settings_for(RaceSetup.race_class, inv_rank)
			(ship as WipeoutShipAI).configure_from_race(settings, circuit, inv_rank)


## Distance along the centerline of the start/finish line. game.c stores it as a
## TRACK.TRS section index (circuit_settings_t.start_line_pos) and the exported
## curve has one point per section, so the line is curve point `start_line`.
## ShipSpawn sits 15 sections earlier, which is why this can't just be the
## spawn's own offset.
func _start_line_offset(center_line: Path3D, track_scene: PackedScene) -> float:
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return 0.0
	var curve := center_line.curve
	var section := TrackSelection.start_line_section_for(track_scene.resource_path)
	var index := posmod(section, curve.point_count)
	return curve.get_closest_offset(curve.get_point_position(index))


## Same idea, but for ShipSpawn's own curve point (start_line - 15, ships_init()'s
## "BASE" section) -- computed from the section index rather than the marker's
## world position so it's exact even though the marker itself sits 2 m higher
## (compute_ship_spawn.py's hover clearance).
func _spawn_offset(center_line: Path3D, track_scene: PackedScene) -> float:
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return 0.0
	var curve := center_line.curve
	var line_section := TrackSelection.start_line_section_for(track_scene.resource_path)
	var index := posmod(line_section - TrackSelection.SPAWN_SECTION_OFFSET, curve.point_count)
	return curve.get_closest_offset(curve.get_point_position(index))


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


func _apply_ship_attributes(ship: WipeoutShip, pilot: String, team: String = "") -> void:
	if ship == null:
		return
	var resolved_team := team
	if resolved_team == "":
		resolved_team = RaceSetup.team_for_pilot(pilot)
	var attributes := RaceSetup.attributes_for(resolved_team, RaceSetup.race_class)
	ship.apply_team_attributes(attributes)

