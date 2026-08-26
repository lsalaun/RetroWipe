extends Control

## Pilot selection: src/wipeout/main_menu.c's page_pilot_init. Pilots are
## restricted to the team chosen on TeamMenu.tscn.

@onready var pilot_list: VBoxContainer = $CenterContainer/VBoxContainer/PilotList
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	for ship in RaceSetup.pilots_for_team(RaceSetup.team_name):
		var button := Button.new()
		button.text = ship["pilot"]
		button.pressed.connect(_on_pilot_selected.bind(ship))
		pilot_list.add_child(button)
	back_button.pressed.connect(_on_back_pressed)
	if pilot_list.get_child_count() > 0:
		pilot_list.get_child(0).grab_focus()


func _on_pilot_selected(ship: Dictionary) -> void:
	RaceSetup.select_pilot(ship)

	if RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP:
		# Championships always start on the first available circuit.
		TrackSelection.select_track(TrackSelection.TRACKS[0]["scene"])
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/CircuitMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TeamMenu.tscn")
