extends Control

## Video options: src/wipeout/main_menu.c's page_options_video_init
## (subset applicable to this port: fullscreen, vsync).

@onready var fullscreen_button: Button = $CenterContainer/VBoxContainer/FullscreenRow/FullscreenButton
@onready var vsync_button: Button = $CenterContainer/VBoxContainer/VsyncRow/VsyncButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	fullscreen_button.button_pressed = Settings.fullscreen
	_refresh_fullscreen_text()
	vsync_button.button_pressed = Settings.vsync
	_refresh_vsync_text()

	fullscreen_button.toggled.connect(_on_fullscreen_toggled)
	vsync_button.toggled.connect(_on_vsync_toggled)
	back_button.pressed.connect(_on_back_pressed)
	GameAudio.hook_menu(self)
	fullscreen_button.grab_focus()


func _on_fullscreen_toggled(value: bool) -> void:
	Settings.set_fullscreen(value)
	_refresh_fullscreen_text()


func _on_vsync_toggled(value: bool) -> void:
	Settings.set_vsync(value)
	_refresh_vsync_text()


func _refresh_fullscreen_text() -> void:
	fullscreen_button.text = "ON" if Settings.fullscreen else "OFF"


func _refresh_vsync_text() -> void:
	vsync_button.text = "ON" if Settings.vsync else "OFF"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsMenu.tscn")
