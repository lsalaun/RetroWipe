extends SceneTree

## Headless check that Track03's long descent does not trip the void/spawn
## reset. The old test froze last_ground_height at the crest; 25 m later the
## ship was still on the racing line but y < crest - margin.

const TRACK_SCENE := "res://scenes/Track03.tscn"
const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const DROP_BELOW_CREST := 40.0
const DRIVE_FRAMES := 150
const MIN_DROP := 25.0

var _frames := 0
var _ship = null
var _track: Node3D = null
var _center_line: Path3D = null
var _started := false
var _spawn_origin := Vector3.ZERO
var _crest_y := 0.0


func _initialize() -> void:
	var track_scene := load(TRACK_SCENE) as PackedScene
	var ship_scene := load(SHIP_SCENE) as PackedScene
	if track_scene == null or ship_scene == null:
		push_error("validate_track03_descent: failed to load scenes")
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
		if not _classify_void() or not _setup_drive():
			quit(1)
			return true
		_started = true
	if not _started:
		return false
	if _frames > 3 + DRIVE_FRAMES:
		return _finish_drive()
	_drive_forward()
	return false


func _classify_void() -> bool:
	_center_line = _track.get_node_or_null("CenterLine") as Path3D
	if _center_line == null or _center_line.curve == null:
		push_error("validate_track03_descent: missing CenterLine")
		return false
	_ship.center_line = _center_line
	var curve: Curve3D = _center_line.curve
	var crest_offset := _crest_offset(curve)
	var crest_local: Vector3 = curve.sample_baked(crest_offset, true)
	_crest_y = _center_line.to_global(crest_local).y
	var down_offset: float = crest_offset
	var down_local: Vector3 = crest_local
	while down_offset < curve.get_baked_length():
		down_local = curve.sample_baked(down_offset, true)
		if _crest_y - _center_line.to_global(down_local).y >= DROP_BELOW_CREST:
			break
		down_offset += 1.0
	var down_world: Vector3 = _center_line.to_global(down_local)
	if _crest_y - down_world.y < DROP_BELOW_CREST:
		push_error("validate_track03_descent: could not find a 40 m drop after the crest")
		return false

	var ahead: Vector3 = curve.sample_baked(down_offset + 1.0, true) - down_local
	ahead.y = 0.0
	if ahead.length_squared() < 0.0001:
		push_error("validate_track03_descent: no forward on descent")
		return false
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(Vector3.UP).normalized()
	var on_track := Transform3D(Basis(right, Vector3.UP, -ahead).orthonormalized(), down_world + Vector3.UP * 2.0)
	_ship.respawn_at(on_track)
	_ship.last_ground_height = _crest_y
	_ship._refresh_track_axes()
	if _ship._is_in_void():
		push_error(
			"validate_track03_descent: on-track ship 40 m below crest classified as void y=%s crest=%s line=%s"
			% [str(_ship.global_position.y), str(_crest_y), str(_ship._track_center_point.y)]
		)
		return false
	print(
		"void_ok crest_y=", snappedf(_crest_y, 0.01),
		" on_track_y=", snappedf(_ship.global_position.y, 0.01),
		" line_y=", snappedf(_ship._track_center_point.y, 0.01)
	)
	return true


func _setup_drive() -> bool:
	var spawn := _track.get_node_or_null("ShipSpawn") as Marker3D
	if spawn == null or _center_line == null or _center_line.curve == null:
		push_error("validate_track03_descent: missing ShipSpawn/CenterLine")
		return false
	_spawn_origin = spawn.global_position
	var curve: Curve3D = _center_line.curve
	var crest_offset := _crest_offset(curve)
	var local: Vector3 = curve.sample_baked(crest_offset, true)
	var ahead: Vector3 = curve.sample_baked(crest_offset + 1.0, true) - local
	ahead.y = 0.0
	if ahead.length_squared() < 0.0001:
		push_error("validate_track03_descent: no forward at crest")
		return false
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(Vector3.UP).normalized()
	var xform := Transform3D(Basis(right, Vector3.UP, -ahead).orthonormalized(), _center_line.to_global(local) + Vector3.UP * 2.0)
	_ship.respawn_at(xform)
	_ship._refresh_track_axes()
	_ship.velocity = ahead * 40.0
	_ship.thrust_mag = _ship.thrust_max
	print("drive_from crest_y=", snappedf(_ship.global_position.y, 0.01))
	return true


func _drive_forward() -> void:
	if _ship == null or _center_line == null or _center_line.curve == null:
		return
	var curve: Curve3D = _center_line.curve
	var offset: float = curve.get_closest_offset(_center_line.to_local(_ship.global_position))
	var ahead: Vector3 = _center_line.to_global(curve.sample_baked(offset + 1.0, true)) - _ship.global_position
	ahead.y = 0.0
	if ahead.length_squared() < 0.0001:
		return
	ahead = ahead.normalized()
	_ship.velocity.x = ahead.x * 40.0
	_ship.velocity.z = ahead.z * 40.0
	_ship.thrust_mag = _ship.thrust_max


func _finish_drive() -> bool:
	var drop: float = _crest_y - _ship.global_position.y
	var back_at_spawn: bool = _ship.global_position.distance_to(_spawn_origin) < 8.0
	print(
		"result frames=", _frames,
		" y=", snappedf(_ship.global_position.y, 0.01),
		" drop=", snappedf(drop, 0.01),
		" spawn_dist=", snappedf(_ship.global_position.distance_to(_spawn_origin), 0.01)
	)
	if back_at_spawn:
		push_error("validate_track03_descent: ship reset to spawn on the descent")
		quit(1)
		return true
	if drop < MIN_DROP:
		push_error("validate_track03_descent: ship did not descend past the old 25 m void margin")
		quit(1)
		return true
	if _ship._is_in_void():
		push_error("validate_track03_descent: ship still on the slope is in the void")
		quit(1)
		return true
	print("validate_track03_descent: OK")
	quit(0)
	return true


func _crest_offset(curve: Curve3D) -> float:
	var best_offset := 0.0
	var best_y := -INF
	var offset := 0.0
	var length: float = curve.get_baked_length()
	while offset <= length:
		var y: float = curve.sample_baked(offset, true).y
		if y > best_y:
			best_y = y
			best_offset = offset
		offset += 4.0
	return best_offset
