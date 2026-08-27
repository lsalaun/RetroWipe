extends SceneTree

## Headless check that Track03's steep banked racing surface is not treated as
## a side wall: place a ship on the known false-positive section and require
## forward progress without wall impacts.

const TRACK_SCENE := "res://scenes/Track03.tscn"
const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const SLOPE_OFFSET := 5600.0
const WAIT_FRAMES := 48
const MIN_PROGRESS := 18.0

var _frames := 0
var _ship = null
var _track: Node3D = null
var _started := false
var _start_progress := 0.0


func _initialize() -> void:
	var track_scene := load(TRACK_SCENE) as PackedScene
	var ship_scene := load(SHIP_SCENE) as PackedScene
	if track_scene == null or ship_scene == null:
		push_error("validate_track03_slope: failed to load scenes")
		quit(1)
		return
	_track = track_scene.instantiate() as Node3D
	root.add_child(_track)
	_ship = ship_scene.instantiate()
	_ship.is_player_controlled = false
	root.add_child(_ship)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		if not _setup():
			quit(1)
			return true
		_started = true
	if not _started:
		return false
	if _frames > 3 + WAIT_FRAMES:
		return _finish()
	_drive_forward()
	return false


func _setup() -> bool:
	var spawn := _track.get_node_or_null("ShipSpawn") as Marker3D
	var center_line := _track.get_node_or_null("CenterLine") as Path3D
	if spawn == null or center_line == null or center_line.curve == null:
		push_error("validate_track03_slope: missing ShipSpawn/CenterLine")
		return false
	_ship.center_line = center_line
	var curve: Curve3D = center_line.curve
	if SLOPE_OFFSET >= curve.get_baked_length():
		push_error("validate_track03_slope: slope offset past curve end")
		return false
	var local := curve.sample_baked(SLOPE_OFFSET, true)
	var ahead := curve.sample_baked(SLOPE_OFFSET + 1.0, true)
	var forward := ahead - local
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		push_error("validate_track03_slope: no forward at slope offset")
		return false
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var xform := Transform3D(Basis(right, Vector3.UP, -forward).orthonormalized(), center_line.to_global(local) + Vector3.UP * 2.0)
	_ship.respawn_at(xform)
	_ship._refresh_track_axes()
	_ship._update_race_progress()
	var floor_n := _ray_normal(Vector3.DOWN * 8.0)
	if floor_n == Vector3.ZERO:
		push_error("validate_track03_slope: no floor under slope sample")
		return false
	if _ship._is_side_wall_normal(floor_n):
		push_error("validate_track03_slope: racing surface classified as wall n=%s" % str(floor_n))
		return false
	_ship.velocity = forward * 40.0
	_ship.thrust_mag = _ship.thrust_max
	_start_progress = _ship.race_progress
	print(
		"setup n=", floor_n,
		" ny=", snappedf(floor_n.y, 0.001),
		" lat=", snappedf(absf(floor_n.dot(_ship._track_right_dir)), 0.001),
		" align=", snappedf(absf(floor_n.dot(_ship._track_floor_normal)), 0.001)
	)
	return true


func _drive_forward() -> void:
	if _ship == null or _ship.center_line == null or _ship.center_line.curve == null:
		return
	var curve: Curve3D = _ship.center_line.curve
	var offset: float = curve.get_closest_offset(_ship.center_line.to_local(_ship.global_position))
	var ahead: Vector3 = _ship.center_line.to_global(curve.sample_baked(offset + 1.0, true))
	var forward: Vector3 = ahead - _ship.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	_ship.velocity.x = forward.x * 40.0
	_ship.velocity.z = forward.z * 40.0
	_ship.thrust_mag = _ship.thrust_max


func _finish() -> bool:
	var progress: float = _ship.race_progress - _start_progress
	print(
		"result frames=", _frames,
		" progress=", snappedf(progress, 0.01),
		" wall_hits=", _ship.wall_hit_count,
		" y=", snappedf(_ship.global_position.y, 0.01)
	)
	if _ship._is_side_wall_normal(_ray_normal(Vector3.DOWN * 8.0)):
		push_error("validate_track03_slope: floor became a wall during the run")
		quit(1)
		return true
	if _ship.wall_hit_count > 0:
		push_error("validate_track03_slope: ship bounced on the racing surface")
		quit(1)
		return true
	if progress < MIN_PROGRESS:
		push_error("validate_track03_slope: ship stalled on the slope")
		quit(1)
		return true
	print("validate_track03_slope: OK")
	quit(0)
	return true


func _ray_normal(target: Vector3) -> Vector3:
	var from: Vector3 = _ship.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + target)
	query.collide_with_areas = false
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["normal"]
