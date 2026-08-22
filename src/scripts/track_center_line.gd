extends Path3D
class_name TrackCenterLine

## Loads the authored racing-line curve for a track, ported from the original
## section->center chain that ship_ai.c follows (see ship_ai_update_race()).
## Blender's glTF export can't preserve Curve objects (a curve with no bevel/
## extrude becomes an empty transform node on export), so the primary source
## is a JSON file of world-space points sampled directly from the .blend file
## by godot/tools/blender/export_track_curve.py. source_scene is kept as a
## secondary source in case a track ever exports its curve as a real Path3D/
## mesh. If neither is usable, a straight placeholder curve is generated so
## the rest of the AI pipeline stays functional.

@export_file("*.json") var source_json: String = ""
@export var source_scene: PackedScene
@export var placeholder_length: float = 100.0


func _ready() -> void:
	if curve and curve.point_count >= 2:
		return

	if source_json != "":
		var loaded := _load_curve_from_json(source_json)
		if loaded:
			curve = loaded
			return

	if source_scene:
		var extracted := _extract_curve_from_scene(source_scene)
		if extracted:
			curve = extracted
			return

	push_warning("TrackCenterLine (%s): no usable curve found, using a straight placeholder. Run godot/tools/blender/export_track_curve.py against the track's .blend file to generate source_json." % name)
	curve = _build_placeholder_curve()


func _load_curve_from_json(path: String) -> Curve3D:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("points"):
		return null

	var raw_points: Array = parsed["points"]
	if raw_points.size() < 2:
		return null

	var result := Curve3D.new()
	for p in raw_points:
		result.add_point(Vector3(p[0], p[1], p[2]))

	var is_loop := bool(parsed.get("closed", false))
	if not is_loop and raw_points.size() >= 2:
		var first := Vector3(raw_points[0][0], raw_points[0][1], raw_points[0][2])
		var last := Vector3(raw_points[-1][0], raw_points[-1][1], raw_points[-1][2])
		is_loop = first.distance_to(last) < 0.1

	result.closed = is_loop
	return result


func _extract_curve_from_scene(scene: PackedScene) -> Curve3D:
	var instance := scene.instantiate()
	var found := _find_curve(instance)
	instance.free()
	return found


func _find_curve(node: Node) -> Curve3D:
	if node is Path3D and node.curve and node.curve.point_count >= 2:
		return node.curve
	for child in node.get_children():
		var result := _find_curve(child)
		if result:
			return result
	return null


func _build_placeholder_curve() -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, placeholder_length * 0.33))
	c.add_point(Vector3(0, 0, placeholder_length), Vector3(0, 0, -placeholder_length * 0.33), Vector3.ZERO)
	return c
