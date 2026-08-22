extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless -s res://tools/inspect_scene.gd -- <res://path/to/scene.glb>")
		quit(1)
		return

	var scene_path := args[0]
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load: %s" % scene_path)
		quit(1)
		return

	var instance := packed.instantiate()
	_print_node(instance, 0)
	instance.free()
	quit(0)


func _print_node(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		var aabb: AABB = node.get_aabb() if mesh else AABB()
		extra = " mesh=%s surfaces=%d aabb=%s" % [mesh.resource_name if mesh else "null", mesh.get_surface_count() if mesh else 0, aabb]
	elif node is Path3D:
		var curve: Curve3D = node.curve
		extra = " curve_points=%d" % (curve.point_count if curve else 0)
	print("%s%s (%s)%s [transform=%s]" % [indent, node.name, node.get_class(), extra, node.transform if node is Node3D else ""])

	for child in node.get_children():
		_print_node(child, depth + 1)
