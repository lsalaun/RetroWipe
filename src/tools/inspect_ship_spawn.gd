extends SceneTree

## Headless check that ShipSpawn sits on racing surface (not void).
## Usage: godot --headless -s res://tools/inspect_ship_spawn.gd -- res://scenes/TrackNN.tscn

const WipeoutShipScript = preload("res://scripts/wipeout_ship.gd")
const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"

var _frames := 0
var _ship = null
var _track: Node3D = null
var _scene_path := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless -s res://tools/inspect_ship_spawn.gd -- <res://scenes/TrackNN.tscn>")
		quit(1)
		return
	_scene_path = args[0]
	var track_scene := load(_scene_path) as PackedScene
	var ship_scene := load(SHIP_SCENE) as PackedScene
	if track_scene == null or ship_scene == null:
		push_error("inspect_ship_spawn: failed to load %s or ship" % _scene_path)
		quit(1)
		return
	_track = track_scene.instantiate() as Node3D
	root.add_child(_track)
	_ship = ship_scene.instantiate()
	_ship.is_player_controlled = false
	root.add_child(_ship)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if not _inspect():
		quit(1)
		return true
	quit(0)
	return true


func _inspect() -> bool:
	var spawn := _track.get_node_or_null("ShipSpawn") as Marker3D
	var center_line := _track.get_node_or_null("CenterLine") as Path3D
	if spawn == null or center_line == null or center_line.curve == null:
		push_error("inspect_ship_spawn: missing ShipSpawn/CenterLine")
		return false
	_ship.center_line = center_line
	_ship.respawn_at(spawn.global_transform)
	_ship._refresh_track_axes()
	var origin: Vector3 = spawn.global_position
	var floor_n := _ray_normal(Vector3.DOWN * 8.0)
	if floor_n == Vector3.ZERO:
		push_error("inspect_ship_spawn: no floor under spawn pos=%s" % str(origin))
		return false
	if _ship._is_side_wall_normal(floor_n):
		push_error("inspect_ship_spawn: spawn floor classified as wall n=%s" % str(floor_n))
		return false
	var curve: Curve3D = center_line.curve
	var local: Vector3 = center_line.to_local(origin)
	var offset: float = curve.get_closest_offset(local)
	var closest: Vector3 = center_line.to_global(curve.sample_baked(offset, true))
	var lateral: Vector3 = origin - closest
	lateral.y = 0.0
	print(
		"inspect_ship_spawn scene=", _scene_path,
		" pos=", origin,
		" floor_n=", floor_n,
		" curve_offset=", snappedf(offset, 0.01),
		" lateral=", snappedf(lateral.length(), 0.01),
		" dy_to_curve=", snappedf(origin.y - closest.y, 0.01)
	)
	print("inspect_ship_spawn: OK")
	return true


func _ray_normal(target: Vector3) -> Vector3:
	var from: Vector3 = _ship.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + target)
	query.collide_with_areas = false
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["normal"]
