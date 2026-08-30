extends Node3D

const RaceFieldScript = preload("res://scripts/race_field.gd")

const TITLE_SCENE := "res://scenes/TitleScreen.tscn"

## title.c's race.c hard cap: the demo returns to the title screen on its own
## even if nothing ever presses a button.
const ATTRACT_MAX_DURATION := 60.0

@export var default_track_scene: PackedScene
@export var ai_ship_scene: PackedScene

var _attract_elapsed: float = 0.0


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

	if RaceSetup.is_attract_mode:
		_setup_attract_race(center_line, spawn, start_line_offset, spawn_offset)
		return

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


# -----------------------------------------------------------------------------
# Attract mode: title.c's idle demo race. Every grid slot is AI-driven; one of
# them is flagged is_player_controlled so the existing camera-chase, HUD-ship
# lookup and RaceDirector "player" plumbing all just follow it instead of a
# human. The scene's own template "Ship" node (a real WipeoutShip, meant for a
# human) is dropped since nobody is playing it.

func _setup_attract_race(center_line: Path3D, spawn: Marker3D, start_line_offset: float, spawn_offset: float) -> void:
	# Removed synchronously, not just queue_free()'d: RaceDirector's own
	# deferred start_race() call (queued in its _ready(), which runs before
	# this one) would otherwise still find this WipeoutShip -- defaulting to
	# is_player_controlled true -- via get_nodes_in_group("ships") and race it
	# against the real POV ship below for RaceDirector.player.
	var placeholder := _find_player_ship()
	if placeholder != null:
		remove_child(placeholder)
		placeholder.queue_free()

	_hide_hud()
	_add_demo_label()
	# pause_menu.gd listens on _input() unconditionally (Escape/Start always
	# opens it), which would both steal the keypress this script wants for
	# _exit_attract_mode() and pause the tree the demo runs on. The original's
	# attract mode has no pause menu either.
	var pause_menu := get_node_or_null("PauseMenu")
	if pause_menu != null:
		pause_menu.process_mode = Node.PROCESS_MODE_DISABLED

	var start_order := RaceFieldScript.build_start_order("")
	var circuit := RaceFieldScript.circuit_settings_for(RaceFieldScript.track_display_name(), RaceSetup.race_class)
	var pov_index := start_order.size() - 1

	for i in start_order.size():
		var entry: Dictionary = start_order[i]
		var inv_rank := (RaceFieldScript.NUM_PILOTS - 1) - i
		var ship := _spawn_ai_ship(i)
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
		var settings := RaceFieldScript.ai_settings_for(RaceSetup.race_class, inv_rank)
		ship.configure_from_race(settings, circuit, inv_rank)

		if i == pov_index:
			# WipeoutShipAI._ready() already cleared these; flip them back so
			# this one slot gets the normal player camera-chase and audio.
			ship.is_player_controlled = true
			var cam := ship.camera_rig.get_node_or_null("Camera3D") as Camera3D
			if cam != null:
				cam.current = true


func _hide_hud() -> void:
	var hud := get_node_or_null("RaceHud")
	if hud != null:
		hud.visible = false


func _add_demo_label() -> void:
	var label := Label.new()
	label.name = "DemoModeLabel"
	label.text = "DEMO MODE"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-60.0, 20.0)
	label.size = Vector2(120.0, 30.0)
	var layer := CanvasLayer.new()
	layer.name = "DemoModeLayer"
	layer.add_child(label)
	add_child(layer)


func _process(delta: float) -> void:
	if not RaceSetup.is_attract_mode:
		return
	_attract_elapsed += delta
	if _attract_elapsed >= ATTRACT_MAX_DURATION:
		_exit_attract_mode()


## Any real button press ends the demo, arcade-attract-mode style; mouse/stick
## motion alone does not, so idling near an input device can't cancel it early.
func _unhandled_input(event: InputEvent) -> void:
	if not RaceSetup.is_attract_mode:
		return
	if not _is_activity_press(event):
		return
	get_viewport().set_input_as_handled()
	_exit_attract_mode()


func _is_activity_press(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return key.pressed and not key.echo
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		return mouse_button.pressed
	var joy_button := event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	return false


func _exit_attract_mode() -> void:
	RaceSetup.is_attract_mode = false
	get_tree().change_scene_to_file(TITLE_SCENE)

