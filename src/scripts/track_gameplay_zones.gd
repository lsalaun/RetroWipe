extends Node3D
class_name TrackGameplayZones

## Spawns gameplay triggers/anchors from the weapon pickup pads, speed boost
## pads and start grid faces exported by godot/tools/psx_track/
## convert_track_face_flags.py (see that script's docstring for the source
## TRACK.TRF flags). Boost pads and weapon pads are functional (see
## track_boost_pad.gd and track_weapon_pad.gd); start grid is a plain
## Marker3D anchor.

const TrackBoostPad = preload("res://scripts/track_boost_pad.gd")
const TrackWeaponPad = preload("res://scripts/track_weapon_pad.gd")

@export_file("*.json") var source_json: String = ""


func _ready() -> void:
	if source_json == "" or not FileAccess.file_exists(source_json):
		return

	var file := FileAccess.open(source_json, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_spawn_weapon_pads(parsed.get("pickup_pads", []))
	_spawn_boost_pads(parsed.get("boost_pads", []))
	_spawn_markers(parsed.get("start_grid", []), "StartGrid", "StartGridFace")


func _spawn_weapon_pads(entries: Array) -> void:
	if entries.is_empty():
		return

	var group := Node3D.new()
	group.name = "WeaponPads"
	add_child(group)

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var center: Array = entry.get("center", [0.0, 0.0, 0.0])
		var pad := TrackWeaponPad.new()
		pad.name = "WeaponPad_%d" % int(entry.get("face_index", i))
		pad.position = Vector3(center[0], center[1], center[2])
		pad.weapon_class = 1  # Give any weapon type
		group.add_child(pad)


func _spawn_boost_pads(entries: Array) -> void:
	if entries.is_empty():
		return

	var group := Node3D.new()
	group.name = "BoostPads"
	add_child(group)

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var center: Array = entry.get("center", [0.0, 0.0, 0.0])
		var pad := TrackBoostPad.new()
		pad.name = "BoostPad_%d" % int(entry.get("face_index", i))
		pad.position = Vector3(center[0], center[1], center[2])
		group.add_child(pad)


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
