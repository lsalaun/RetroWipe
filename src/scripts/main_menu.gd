extends Control

## Top-level menu: src/wipeout/main_menu.c's page_main_init
## (START GAME / OPTIONS / QUIT).

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var options_button: Button = $CenterContainer/VBoxContainer/OptionsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
@onready var quit_confirm: ConfirmationDialog = $QuitConfirmDialog


func _ready() -> void:
	MenuBackdrop.attach(self)
	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_confirm.confirmed.connect(_on_quit_confirmed)
	GameAudio.hook_menu(self)
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RaceClassMenu.tscn")


func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsMenu.tscn")


func _on_quit_pressed() -> void:
	quit_confirm.popup_centered()


func _on_quit_confirmed() -> void:
	get_tree().quit()
