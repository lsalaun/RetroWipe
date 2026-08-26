extends SceneTree

## Headless check that Wipeout edge shelves are treated as walls, not hoverable
## ramps. Places a ship on Track01, samples floor vs shelf normals, then drives
## it into the right-hand shelf and asserts it is pushed back instead of climbing.

const WipeoutShipScript = preload("res://scripts/wipeout_ship.gd")

const WAIT_FRAMES := 36
const TRACK_SCENE := "res://scenes/Track01.tscn"
const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"

var _frames := 0
var _ship = null
var _track: Node3D = null
var _started := false
var _start_y := 0.0
var _start_lateral := 0.0
var _max_y := 0.0
var _saw_wall := false
var _min_lateral := 999.0
var _failed := false


func _initialize() -> void:
	var track_scene := load(TRACK_SCENE) as PackedScene
	var ship_scene := load(SHIP_SCENE) as PackedScene
	if track_scene == null or ship_scene == null:
		push_error("validate_track_side_walls: failed to load scenes")
		quit(1)
		return

	_track = track_scene.instantiate() as Node3D
	root.add_child(_track)
	_ship = ship_scene.instantiate()
	_ship.is_player_controlled = false
	root.add_child(_ship)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# SceneTree._initialize add_child does not guarantee _ready / in-tree
	# global transforms yet; wait a couple of physics ticks.
	if _frames == 3:
		if not _setup_and_classify():
			quit(1)
			return true
		_started = true
	if not _started:
		return false
	if _frames > 3 + WAIT_FRAMES:
		return _finish()

	_sample_motion()
	# Keep driving into the right-hand shelf after the initial shove.
	var shove: Vector3 = _ship._track_right_dir
	_ship.velocity.x = shove.x * 40.0 + _ship.velocity.x * 0.15
	_ship.velocity.z = shove.z * 40.0 + _ship.velocity.z * 0.15
	return false


func _setup_and_classify() -> bool:
	var spawn := _track.get_node_or_null("ShipSpawn") as Marker3D
	var center_line := _track.get_node_or_null("CenterLine") as Path3D
	if spawn == null or center_line == null or center_line.curve == null:
		push_error("validate_track_side_walls: missing ShipSpawn/CenterLine")
		return false
	_ship.center_line = center_line
	_ship.respawn_at(spawn.global_transform)

	if _ship.center_line == null or _ship.center_line.curve == null:
		push_error("validate_track_side_walls: center line curve not ready")
		return false

	_ship._refresh_track_axes()
	var floor_n := _ray_normal(Vector3.DOWN * 8.0)
	if floor_n == Vector3.ZERO:
		push_error("validate_track_side_walls: no floor under spawn")
		return false
	if _ship._is_side_wall_normal(floor_n):
		push_error("validate_track_side_walls: spawn floor classified as wall n=%s" % str(floor_n))
		return false

	var right: Vector3 = _ship._track_right_dir
	# Edge shelves on TRACK01 start ~18–20 m off the racing line.
	_ship.global_position += right * 18.0
	_ship.velocity = right * 28.0
	_start_y = _ship.global_position.y
	_start_lateral = _lateral_offset()
	_max_y = _start_y
	_min_lateral = _start_lateral
	print(
		"setup y=", snappedf(_start_y, 0.01),
		" lateral=", snappedf(_start_lateral, 0.01),
		" floor_n=", floor_n,
		" track_right=", right
	)
	return true


func _sample_motion() -> void:
	if _ship == null:
		return
	_max_y = maxf(_max_y, _ship.global_position.y)
	_min_lateral = minf(_min_lateral, _lateral_offset())
	if _ship.wall_impact_cooldown > 0.0:
		_saw_wall = true


func _finish() -> bool:
	var climb := _max_y - _start_y
	var lateral_now := _lateral_offset()
	print(
		"result frames=", _frames,
		" climb=", snappedf(climb, 0.01),
		" lateral_start=", snappedf(_start_lateral, 0.01),
		" lateral_min=", snappedf(_min_lateral, 0.01),
		" lateral_end=", snappedf(lateral_now, 0.01),
		" saw_wall=", _saw_wall,
		" y=", snappedf(_ship.global_position.y, 0.01)
	)
	# A climbed shelf raises the ship several metres; a bounce stays near hover height.
	if climb > 3.5:
		push_error("validate_track_side_walls: ship climbed the edge shelf")
		_failed = true
	if not _saw_wall and _min_lateral > _start_lateral + 4.0:
		push_error("validate_track_side_walls: ship slid onto the shelf with no wall hit")
		_failed = true
	if _failed:
		quit(1)
		return true
	print("validate_track_side_walls: OK")
	quit(0)
	return true


func _lateral_offset() -> float:
	if _ship == null or _ship.center_line == null or _ship.center_line.curve == null:
		return 0.0
	var curve: Curve3D = _ship.center_line.curve
	var local: Vector3 = _ship.center_line.to_local(_ship.global_position)
	var offset: float = curve.get_closest_offset(local)
	var closest: Vector3 = _ship.center_line.to_global(curve.sample_baked(offset, true))
	var delta: Vector3 = _ship.global_position - closest
	delta.y = 0.0
	return delta.length()


func _ray_normal(target: Vector3) -> Vector3:
	var from: Vector3 = _ship.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + target)
	query.collide_with_areas = false
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["normal"]
