extends Control

## Race type selection: src/wipeout/main_menu.c's page_race_type_init
## (CHAMPIONSHIP RACE / SINGLE RACE / TIME TRIAL).

@onready var option_list: VBoxContainer = $CenterContainer/VBoxContainer/OptionList
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	for i in RaceSetup.RACE_TYPES.size():
		var button := Button.new()
		button.text = RaceSetup.RACE_TYPES[i]
		button.pressed.connect(_on_type_selected.bind(i))
		option_list.add_child(button)
	back_button.pressed.connect(_on_back_pressed)
	option_list.get_child(0).grab_focus()


func _on_type_selected(index: int) -> void:
	RaceSetup.select_race_type(index)
	get_tree().change_scene_to_file("res://scenes/TeamMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RaceClassMenu.tscn")
