extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("main scene failed")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	await physics_frame
	var track := main.get_node_or_null("Track") as Node3D
	var center_line := track.get_node_or_null("CenterLine") as Path3D
	if center_line == null or center_line.curve == null:
		push_error("No track center line")
		quit(1)
		return
	for name in ["Ship", "ShipAI1", "ShipAI2"]:
		var ship := main.get_node_or_null(name) as Node3D
		if ship == null:
			continue
		var local := center_line.to_local(ship.global_position)
		var offset := center_line.curve.get_closest_offset(local)
		var sampled := center_line.curve.sample_baked(offset, true)
		var dir := center_line.curve.sample_baked(offset + 1.0, true) - sampled
		var lateral := (ship.global_position - center_line.to_global(sampled))
		lateral.y = 0.0
		print(name, " pos=", ship.global_position)
		print("  closest_offset=", offset)
		print("  sampled=", center_line.to_global(sampled))
		print("  lateral_error=", lateral.length())
		print("  dir=", dir.normalized())
	print("curve_points=", center_line.curve.point_count)
	print("first=", center_line.curve.get_point_position(0))
	print("last=", center_line.curve.get_point_position(center_line.curve.point_count - 1))
	quit()
