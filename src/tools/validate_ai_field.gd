extends SceneTree

## Headless check that the race field spawns 7 DPA opponents plus the player
## and that they start following the center line.

const WAIT_FRAMES := 48

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
	for node in get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship == null:
			continue
		print(ship.name, " rank=", ship.position_rank, " progress=", snappedf(ship.race_progress, 0.01), " speed=", snappedf(ship.velocity.length(), 0.01), " left=", ship.on_left_side)
		if ship is WipeoutShipAI and ship.velocity.length() > 2.0:
			moving += 1
		ranks[ship.position_rank] = true
	print("moving_ai=", moving, " unique_ranks=", ranks.size())
	if moving < 5:
		push_error("expected most AI ships to be moving")
		return false
	if ranks.size() != 8:
		push_error("expected unique ranks 1-8")
		return false
	return true
