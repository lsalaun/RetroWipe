extends Node3D
class_name Track01Test

## Standalone playable scene for exercising the Track_01 Blender assets
## (mesh + authored curve) with a ship, independent of main.tscn.

func _ready() -> void:
	var track := get_node_or_null(^"Track01")
	var ship := get_node_or_null(^"Ship")
	if track == null or ship == null:
		return

	var center_line := track.get_node_or_null(^"CenterLine") as Path3D
	if center_line:
		ship.center_line = center_line
