extends Control

## Controls remapping: src/wipeout/main_menu.c's page_options_controls_init
## / button_capture. One row per rebindable action with a KEYBOARD and a
## JOYSTICK button; pressing either awaits the next matching input event.

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

@onready var grid: GridContainer = $CenterContainer/VBoxContainer/Grid
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _capturing_action: String = ""
var _capturing_is_pad: bool = false


func _ready() -> void:
	MenuBackdrop.attach(self)
	_populate()
	back_button.pressed.connect(_on_back_pressed)


func _populate() -> void:
	for child in grid.get_children():
		child.queue_free()

	var first_button: Button = null
	for action in Settings.REBINDABLE_ACTIONS:
		var label := Label.new()
		label.text = action.trim_prefix("ship_").replace("_", " ").to_upper()
		label.custom_minimum_size = Vector2(140, 0)
		grid.add_child(label)

		var key_button := Button.new()
		key_button.text = Settings.get_key_display_name(action)
		key_button.custom_minimum_size = Vector2(100, 0)
		key_button.pressed.connect(_start_capture.bind(action, false))
		grid.add_child(key_button)
		if first_button == null:
			first_button = key_button

		var pad_button := Button.new()
		pad_button.text = Settings.get_pad_display_name(action)
		pad_button.custom_minimum_size = Vector2(100, 0)
		pad_button.pressed.connect(_start_capture.bind(action, true))
		grid.add_child(pad_button)

	GameAudio.hook_menu(self)
	if first_button:
		first_button.grab_focus()


func _start_capture(action: String, is_pad: bool) -> void:
	_capturing_action = action
	_capturing_is_pad = is_pad
	status_label.text = "PRESS A BUTTON (ESC TO CANCEL)" if is_pad else "PRESS A KEY (ESC TO CANCEL)"


func _unhandled_input(event: InputEvent) -> void:
	if _capturing_action == "":
		return

	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			return
		if not _capturing_is_pad:
			Settings.rebind_key(_capturing_action, event.physical_keycode)
			_finish_capture()
	elif event is InputEventJoypadButton and event.pressed and _capturing_is_pad:
		get_viewport().set_input_as_handled()
		Settings.rebind_pad(_capturing_action, event.button_index)
		_finish_capture()


func _cancel_capture() -> void:
	_capturing_action = ""
	status_label.text = ""


func _finish_capture() -> void:
	_capturing_action = ""
	status_label.text = ""
	_populate()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsMenu.tscn")
