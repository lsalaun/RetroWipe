extends Node3D

@export var default_track_scene: PackedScene

## Local-space (right, up, behind) offset from the track's ShipSpawn marker,
## applied in child order: player ship first, then each AI ship.
const GRID_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(3.0, 0.0, 2.0),
	Vector3(-3.0, 0.0, 2.0),
]


func _ready() -> void:
	var track_scene: PackedScene = default_track_scene
	if TrackSelection.selected_track_scene != null:
		track_scene = TrackSelection.selected_track_scene

	var track := track_scene.instantiate()
	track.name = "Track"
	add_child(track)
	move_child(track, 0)

	var center_line := track.get_node_or_null("CenterLine") as Path3D
	var spawn := track.get_node_or_null("ShipSpawn") as Marker3D

	var ship_index := 0
	for child in get_children():
		if child is WipeoutShip:
			child.center_line = center_line
			if spawn and ship_index < GRID_OFFSETS.size():
				child.global_transform = spawn.global_transform.translated_local(GRID_OFFSETS[ship_index])
			ship_index += 1
