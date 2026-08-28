extends Control

## Race class selection: src/wipeout/main_menu.c's page_race_class_init
## (VENOM CLASS / RAPIER CLASS).

@onready var option_list: VBoxContainer = $CenterContainer/VBoxContainer/OptionList
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	for i in RaceSetup.RACE_CLASSES.size():
		var button := Button.new()
		button.text = RaceSetup.RACE_CLASSES[i]
		button.pressed.connect(_on_class_selected.bind(i))
		option_list.add_child(button)
	back_button.pressed.connect(_on_back_pressed)
	GameAudio.hook_menu(self)
	option_list.get_child(0).grab_focus()


func _on_class_selected(index: int) -> void:
	RaceSetup.select_race_class(index)
	get_tree().change_scene_to_file("res://scenes/RaceTypeMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
