extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless -s inspect_scene.gd -- res://path/to/scene.glb")
		quit(1)
		return

	var path := args[0]
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Failed to load %s" % path)
		quit(1)
		return

	var root := packed.instantiate()
	_dump(root, 0)
	quit(0)


func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		extra = " mesh=%s" % str(node.mesh)
	if node is Path3D:
		var curve: Curve3D = node.curve
		extra = " curve_points=%d closed=%s" % [curve.point_count if curve else -1, curve.point_count > 0 and curve.get_point_position(0) == curve.get_point_position(curve.point_count - 1)]
	print("%s%s (%s)%s" % [indent, node.name, node.get_class(), extra])
	for child in node.get_children():
		_dump(child, depth + 1)
