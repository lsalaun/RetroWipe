extends Control

## Populates a button per entry in TrackSelection.TRACKS and launches
## main.tscn with the chosen track when pressed.

@onready var track_list: VBoxContainer = $CenterContainer/VBoxContainer/TrackList


func _ready() -> void:
	for track in TrackSelection.TRACKS:
		var button := Button.new()
		button.text = track["name"]
		button.pressed.connect(_on_track_selected.bind(track["scene"]))
		track_list.add_child(button)


func _on_track_selected(scene_path: String) -> void:
	TrackSelection.select_track(scene_path)
	get_tree().change_scene_to_file("res://scenes/ShipSelectionMenu.tscn")
