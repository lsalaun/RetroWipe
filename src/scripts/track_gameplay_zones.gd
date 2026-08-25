extends Node3D
class_name TrackGameplayZones

## Spawns Marker3D placeholders for the weapon pickup pads, speed boost pads
## and start grid faces exported by godot/tools/psx_track/
## convert_track_face_flags.py (see that script's docstring for the source
## TRACK.TRF flags). No gameplay behavior is attached yet -- these are meant
## as anchor points for a future pickup/boost system to hook into.

@export_file("*.json") var source_json: String = ""


func _ready() -> void:
	if source_json == "" or not FileAccess.file_exists(source_json):
		return

	var file := FileAccess.open(source_json, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_spawn_markers(parsed.get("pickup_pads", []), "PickupPads", "PickupPad")
	_spawn_markers(parsed.get("boost_pads", []), "BoostPads", "BoostPad")
	_spawn_markers(parsed.get("start_grid", []), "StartGrid", "StartGridFace")


func _spawn_markers(entries: Array, group_name: String, marker_prefix: String) -> void:
	if entries.is_empty():
		return

	var group := Node3D.new()
	group.name = group_name
	add_child(group)

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var center: Array = entry.get("center", [0.0, 0.0, 0.0])
		var side: String = entry.get("side", "")
		var marker := Marker3D.new()
		marker.name = "%s_%d%s" % [marker_prefix, int(entry.get("face_index", i)), ("_" + side) if side != "" else ""]
		marker.position = Vector3(center[0], center[1], center[2])
		group.add_child(marker)
