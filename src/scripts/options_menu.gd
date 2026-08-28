extends Control

## Options root: src/wipeout/main_menu.c's page_options_init
## (CONTROLS / VIDEO / AUDIO).

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

@onready var controls_button: Button = $CenterContainer/VBoxContainer/ControlsButton
@onready var video_button: Button = $CenterContainer/VBoxContainer/VideoButton
@onready var audio_button: Button = $CenterContainer/VBoxContainer/AudioButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	MenuBackdrop.attach(self)
	controls_button.pressed.connect(_on_controls_pressed)
	video_button.pressed.connect(_on_video_pressed)
	audio_button.pressed.connect(_on_audio_pressed)
	back_button.pressed.connect(_on_back_pressed)
	GameAudio.hook_menu(self)
	controls_button.grab_focus()


func _on_controls_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsControlsMenu.tscn")


func _on_video_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsVideoMenu.tscn")


func _on_audio_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsAudioMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
