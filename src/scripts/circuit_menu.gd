extends Control

## Circuit selection: src/wipeout/main_menu.c's page_circuit_init. Only
## reached for SINGLE RACE / TIME TRIAL; championships always start on the
## first circuit (see pilot_menu.gd).

@onready var circuit_list: VBoxContainer = $CenterContainer/VBoxContainer/CircuitList
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	for track in TrackSelection.TRACKS:
		var button := Button.new()
		button.text = track["name"]
		button.pressed.connect(_on_circuit_selected.bind(track["scene"]))
		circuit_list.add_child(button)
	back_button.pressed.connect(_on_back_pressed)
	if circuit_list.get_child_count() > 0:
		circuit_list.get_child(0).grab_focus()


func _on_circuit_selected(scene_path: String) -> void:
	TrackSelection.select_track(scene_path)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PilotMenu.tscn")
