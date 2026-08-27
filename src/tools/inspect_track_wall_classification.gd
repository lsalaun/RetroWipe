extends SceneTree

## Samples floor normals along a track center line and reports how often
## the current ship wall heuristic would treat the racing surface as a wall.

const WipeoutShipScript = preload("res://scripts/wipeout_ship.gd")

const TRACK_SCENE := "res://scenes/Track03.tscn"
const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const STEP_M := 4.0
const RAY_DOWN := 12.0

var _frames := 0
var _track: Node3D = null
var _ship = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var track_path := TRACK_SCENE if args.is_empty() else args[0]
	var track_scene := load(track_path) as PackedScene
	var ship_scene := load(SHIP_SCENE) as PackedScene
	if track_scene == null or ship_scene == null:
		push_error("inspect_track_wall_classification: failed to load scenes")
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
	if not _sample():
		quit(1)
		return true
	quit(0)
	return true


func _sample() -> bool:
	var center_line := _track.get_node_or_null("CenterLine") as Path3D
	if center_line == null or center_line.curve == null:
		push_error("inspect_track_wall_classification: missing CenterLine")
		return false
	_ship.center_line = center_line
	var curve: Curve3D = center_line.curve
	var length := curve.get_baked_length()
	var samples := 0
	var wall_hits := 0
	var shelf_hits := 0
	var shelf_walls := 0
	var max_lat := 0.0
	var max_ny := 0.0
	var min_ny := 1.0
	var worst := ""
	var offset := 0.0
	while offset <= length:
		var local := curve.sample_baked(offset, true)
		var world := center_line.to_global(local)
		var probe := world + Vector3.UP * 2.0
		_ship.global_position = probe
		_ship._refresh_track_axes()
		var hit := _ray(probe, Vector3.DOWN * RAY_DOWN)
		samples += 1
		if hit.is_empty():
			offset += STEP_M
			continue
		var n: Vector3 = hit["normal"]
		var lat := absf(n.dot(_ship._track_right_dir))
		var classified: bool = _ship._is_side_wall_normal(n)
		max_lat = maxf(max_lat, lat)
		max_ny = maxf(max_ny, absf(n.y))
		min_ny = minf(min_ny, absf(n.y))
		if classified:
			wall_hits += 1
			worst = "offset=%.1f n=%s ny=%.3f lat=%.3f floor=%s right=%s" % [
				offset, n, n.y, lat, _ship._track_floor_normal, _ship._track_right_dir
			]
			print(
				"WALL offset=", snappedf(offset, 0.1),
				" ny=", snappedf(n.y, 0.001),
				" lat=", snappedf(lat, 0.001),
				" align=", snappedf(absf(n.dot(_ship._track_floor_normal)), 0.001)
			)
		var shelf_from: Vector3 = probe + _ship._track_right_dir * 18.0
		var shelf := _ray(shelf_from, Vector3.DOWN * RAY_DOWN)
		if not shelf.is_empty():
			shelf_hits += 1
			var sn: Vector3 = shelf["normal"]
			if _ship._is_side_wall_normal(sn):
				shelf_walls += 1
		offset += STEP_M
	print(
		"track=", _track.scene_file_path,
		" samples=", samples,
		" false_walls=", wall_hits,
		" shelf_hits=", shelf_hits,
		" shelf_walls=", shelf_walls,
		" max_lat=", snappedf(max_lat, 0.001),
		" min_ny=", snappedf(min_ny, 0.001),
		" max_ny=", snappedf(max_ny, 0.001)
	)
	if worst != "":
		print("example ", worst)
	if wall_hits > 0:
		push_error("inspect_track_wall_classification: racing surface classified as wall")
		return false
	return true


func _ray(from: Vector3, target: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + target)
	query.collide_with_areas = false
	return root.get_world_3d().direct_space_state.intersect_ray(query)
