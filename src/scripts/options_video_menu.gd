extends Control

## Video options: src/wipeout/main_menu.c's page_options_video_init
## (subset applicable to this port: fullscreen, vsync, plus save.draw_stats'
## FPS readout as a plain on/off toggle).

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

@onready var fullscreen_button: Button = $CenterContainer/VBoxContainer/FullscreenRow/FullscreenButton
@onready var vsync_button: Button = $CenterContainer/VBoxContainer/VsyncRow/VsyncButton
@onready var show_fps_button: Button = $CenterContainer/VBoxContainer/ShowFpsRow/ShowFpsButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	MenuBackdrop.attach(self)
	fullscreen_button.button_pressed = Settings.fullscreen
	_refresh_fullscreen_text()
	vsync_button.button_pressed = Settings.vsync
	_refresh_vsync_text()
	show_fps_button.button_pressed = Settings.show_fps
	_refresh_show_fps_text()

	fullscreen_button.toggled.connect(_on_fullscreen_toggled)
	vsync_button.toggled.connect(_on_vsync_toggled)
	show_fps_button.toggled.connect(_on_show_fps_toggled)
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


func _on_show_fps_toggled(value: bool) -> void:
	Settings.set_show_fps(value)
	_refresh_show_fps_text()


func _refresh_vsync_text() -> void:
	vsync_button.text = "ON" if Settings.vsync else "OFF"


func _refresh_show_fps_text() -> void:
	show_fps_button.text = "ON" if Settings.show_fps else "OFF"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsMenu.tscn")
