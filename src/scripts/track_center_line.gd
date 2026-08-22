extends Path3D
class_name TrackCenterLine

## Loads the authored racing-line curve for a track, ported from the original
## section->center chain that ship_ai.c follows (see ship_ai_update_race()).
## The Blender export pipeline currently can't preserve curve/spline data
## through glTF (a Blender Curve object with no mesh becomes an empty
## transform node), so source_scene is checked for a usable Path3D and, if
## none is found, a straight placeholder curve is generated instead so the
## rest of the AI pipeline stays functional until the real spline is exported
## (e.g. by converting the curve to a mesh/polyline in Blender before export).

@export var source_scene: PackedScene
@export var placeholder_length: float = 100.0


func _ready() -> void:
	if curve and curve.point_count >= 2:
		return

	if source_scene:
		var extracted := _extract_curve_from_scene(source_scene)
		if extracted:
			curve = extracted
			return

	push_warning("TrackCenterLine (%s): no usable curve found in source_scene, using a straight placeholder. Re-export the Blender curve (e.g. Convert To > Mesh) so it survives the glTF import." % name)
	curve = _build_placeholder_curve()


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
