@tool
extends EditorScript

## Validation tool for weapon pads on tracks
## Checks that all weapon pads are properly placed and configured

class_name ValidateWeaponPads


func _run() -> void:
	var scene = get_scene()
	if scene == null:
		print("ERROR: No scene loaded")
		return

	var issues = []

	# Find all weapon pads
	var weapon_pads = _find_nodes_of_type(scene, "TrackWeaponPad")
	if weapon_pads.is_empty():
		print("WARNING: No weapon pads found on track")
		return

	print("Found %d weapon pads" % weapon_pads.size())

	# Check each pad
	for i in range(weapon_pads.size()):
		var pad = weapon_pads[i]
		var pad_issues = _validate_pad(pad, i)
		issues.append_array(pad_issues)

	# Print results
	if issues.is_empty():
		print("✓ All weapon pads are valid")
	else:
		print("ERROR: Found %d issues:" % issues.size())
		for issue in issues:
			print("  - %s" % issue)


func _validate_pad(pad: Node3D, index: int) -> Array:
	"""Validate a single weapon pad"""
	var issues = []

	# Check if pad is a TrackWeaponPad
	if not pad.get_script():
		issues.append("Pad %d: Missing script" % index)
		return issues

	# Check position
	if pad.global_position == Vector3.ZERO:
		issues.append("Pad %d (%s): Position is at origin" % [index, pad.name])

	# Check collision shape exists
	var collision_shapes = _find_nodes_of_type(pad, "CollisionShape3D")
	if collision_shapes.is_empty():
		issues.append("Pad %d (%s): No collision shape found" % [index, pad.name])

	# Check if pad has visual
	var visual = pad.get_node_or_null("Visual")
	if not visual:
		print("  WARNING: Pad %d (%s): No visual representation" % [index, pad.name])

	return issues


func _find_nodes_of_type(root: Node, class_name: String) -> Array:
	"""Find all nodes of a specific class"""
	var results = []

	if root.get_class() == class_name or root.is_class(class_name):
		results.append(root)

	for child in root.get_children():
		results.append_array(_find_nodes_of_type(child, class_name))

	return results
