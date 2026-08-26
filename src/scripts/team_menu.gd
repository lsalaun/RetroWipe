extends Control

## Team selection: src/wipeout/main_menu.c's page_team_init.

@onready var option_list: VBoxContainer = $CenterContainer/VBoxContainer/OptionList
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	for team_name in RaceSetup.TEAM_ORDER:
		var button := Button.new()
		button.text = team_name
		button.pressed.connect(_on_team_selected.bind(team_name))
		option_list.add_child(button)
	back_button.pressed.connect(_on_back_pressed)
	option_list.get_child(0).grab_focus()


func _on_team_selected(team_name: String) -> void:
	RaceSetup.select_team(team_name)
	get_tree().change_scene_to_file("res://scenes/PilotMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RaceTypeMenu.tscn")
