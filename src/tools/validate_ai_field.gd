extends SceneTree

## Headless check that the race field spawns 7 DPA opponents plus the player
## and that they start following the center line without wall ping-pong.

## RaceDirector gates the whole grid for ship.h's UPDATE_TIME_INITIAL (200/30 s,
## ~400 physics frames at 60 Hz) before GO, so the motion check has to sit well
## past the countdown.
const WAIT_FRAMES := 600
## A remote holding a DPA lane sits a quarter of the track width off centre --
## about 9.5 m on Terramax (see WipeoutShipAI._lane_offset_magnitude). This
## bound is there to catch a ship that has left the road, not one that is
## deliberately hugging a side.
const MAX_AI_LATERAL := 12.0
const MAX_AI_WALL_HITS := 8

var _frames := 0
var _main: Node3D = null


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("main.tscn failed to load")
		quit(1)
		return
	_main = scene.instantiate() as Node3D
	root.add_child(_main)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	if _frames == 2:
		if not _check_spawn():
			quit(1)
			return true
	if _frames < WAIT_FRAMES:
		return false
	if not _check_motion():
		quit(1)
		return true
	print("validate_ai_field: OK")
	quit(0)
	return true


func _check_spawn() -> bool:
	var ships := get_nodes_in_group(&"ships")
	var ai_count := 0
	var player_count := 0
	for node in ships:
		var ship := node as WipeoutShip
		if ship == null:
			continue
		if ship.is_player_controlled:
			player_count += 1
		elif ship is WipeoutShipAI:
			ai_count += 1
			var ai := ship as WipeoutShipAI
			if ai.remote_speed_max <= 0.0:
				push_error("AI %s has no remote_speed_max" % ship.name)
				return false
			if ai.center_line == null or ai.center_line.curve == null:
				push_error("AI %s has no center_line" % ship.name)
				return false
	print("spawn ships=", ships.size(), " ai=", ai_count, " player=", player_count)
	if ships.size() != 8 or ai_count != 7 or player_count != 1:
		push_error("expected 8 ships (7 AI + 1 player)")
		return false
	return true


func _check_motion() -> bool:
	var moving := 0
	var ranks: Dictionary = {}
	var wall_fail := false
	var lateral_fail := false
	for node in get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship == null:
			continue
		var lateral := _lateral_error(ship)
		var strat := ""
		if ship is WipeoutShipAI:
			strat = str((ship as WipeoutShipAI).strategy)
		print(ship.name, " rank=", ship.position_rank, " progress=", snappedf(ship.race_progress, 0.01), " speed=", snappedf(ship.velocity.length(), 0.01), " left=", ship.on_left_side, " lateral=", snappedf(lateral, 0.01), " walls=", ship.wall_hit_count, " strat=", strat)
		if ship is WipeoutShipAI and ship.velocity.length() > 2.0:
			moving += 1
		if ship is WipeoutShipAI and ship.wall_hit_count > MAX_AI_WALL_HITS:
			push_error("%s wall ping-pong: hits=%d" % [ship.name, ship.wall_hit_count])
			wall_fail = true
		if ship is WipeoutShipAI and lateral > MAX_AI_LATERAL:
			push_error("%s drifted off racing line: lateral=%s" % [ship.name, str(snappedf(lateral, 0.01))])
			lateral_fail = true
		ranks[ship.position_rank] = true
	print("moving_ai=", moving, " unique_ranks=", ranks.size())
	if moving < 5:
		push_error("expected most AI ships to be moving")
		return false
	if ranks.size() != 8:
		push_error("expected unique ranks 1-8")
		return false
	if wall_fail or lateral_fail:
		return false
	return true


func _lateral_error(ship: WipeoutShip) -> float:
	if ship.center_line == null or ship.center_line.curve == null or ship.center_line.curve.point_count < 2:
		return 0.0
	var curve := ship.center_line.curve
	var closest := ship.center_line.to_global(curve.sample_baked(curve.get_closest_offset(ship.center_line.to_local(ship.global_position)), true))
	var lateral := ship.global_position - closest
	lateral.y = 0.0
	return lateral.length()
