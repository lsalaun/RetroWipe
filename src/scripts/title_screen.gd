extends Control

## Title splash: src/wipeout/title.c (wiptitle.tim + PRESS ENTER).

const MAIN_MENU := "res://scenes/MainMenu.tscn"

@onready var start_button: Button = $StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	GameAudio.hook_menu(self)
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_start_pressed()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
