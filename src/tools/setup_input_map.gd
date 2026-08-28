extends SceneTree


func _initialize() -> void:
	var serialized_actions := _ensure_input_map_defaults()
	_dump_serialized_actions(serialized_actions)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		push_error("Failed to save project settings: %s" % error_string(save_error))
	quit(save_error)


func _ensure_input_map_defaults() -> Dictionary:
	var serialized_actions := {}
	# Built-in UI actions. setup_input_map used to write only ship_* and
	# ProjectSettings.save() dropped Godot's defaults, so menus could move
	# focus (sometimes) but never confirm with the south face button.
	serialized_actions[String(&"ui_accept")] = _ensure_action(&"ui_accept", 0.5, [
		_ui_key_event(KEY_ENTER),
		_ui_key_event(KEY_KP_ENTER),
		_ui_key_event(KEY_SPACE),
		_joypad_button_event(JOY_BUTTON_A),
	])
	serialized_actions[String(&"ui_select")] = _ensure_action(&"ui_select", 0.5, [
		_ui_key_event(KEY_SPACE),
		_joypad_button_event(JOY_BUTTON_X),
	])
	serialized_actions[String(&"ui_cancel")] = _ensure_action(&"ui_cancel", 0.5, [
		_ui_key_event(KEY_ESCAPE),
		_joypad_button_event(JOY_BUTTON_B),
	])
	serialized_actions[String(&"ui_focus_next")] = _ensure_action(&"ui_focus_next", 0.5, [
		_ui_key_event(KEY_TAB),
	])
	serialized_actions[String(&"ui_focus_prev")] = _ensure_action(&"ui_focus_prev", 0.5, [
		_ui_key_event(KEY_TAB, true),
	])
	serialized_actions[String(&"ui_left")] = _ensure_action(&"ui_left", 0.5, [
		_ui_key_event(KEY_LEFT),
		_joypad_button_event(JOY_BUTTON_DPAD_LEFT),
		_joypad_motion_event(JOY_AXIS_LEFT_X, -1.0),
	])
	serialized_actions[String(&"ui_right")] = _ensure_action(&"ui_right", 0.5, [
		_ui_key_event(KEY_RIGHT),
		_joypad_button_event(JOY_BUTTON_DPAD_RIGHT),
		_joypad_motion_event(JOY_AXIS_LEFT_X, 1.0),
	])
	serialized_actions[String(&"ui_up")] = _ensure_action(&"ui_up", 0.5, [
		_ui_key_event(KEY_UP),
		_joypad_button_event(JOY_BUTTON_DPAD_UP),
		_joypad_motion_event(JOY_AXIS_LEFT_Y, -1.0),
	])
	serialized_actions[String(&"ui_down")] = _ensure_action(&"ui_down", 0.5, [
		_ui_key_event(KEY_DOWN),
		_joypad_button_event(JOY_BUTTON_DPAD_DOWN),
		_joypad_motion_event(JOY_AXIS_LEFT_Y, 1.0),
	])
	serialized_actions[String(&"ship_thrust")] = _ensure_action(&"ship_thrust", 0.2, [
		_key_event(KEY_W),
		_joypad_motion_event(JOY_AXIS_LEFT_Y, -1.0),
		_joypad_motion_event(JOY_AXIS_TRIGGER_RIGHT, 1.0),
		_joypad_button_event(JOY_BUTTON_A), # south face button: Xbox "A" / PlayStation "X" (Cross)
	])
	serialized_actions[String(&"ship_reverse")] = _ensure_action(&"ship_reverse", 0.2, [
		_key_event(KEY_S),
		_joypad_motion_event(JOY_AXIS_LEFT_Y, 1.0),
	])
	serialized_actions[String(&"ship_steer_left")] = _ensure_action(&"ship_steer_left", 0.2, [
		_key_event(KEY_A),
		_joypad_motion_event(JOY_AXIS_LEFT_X, -1.0),
	])
	serialized_actions[String(&"ship_steer_right")] = _ensure_action(&"ship_steer_right", 0.2, [
		_key_event(KEY_D),
		_joypad_motion_event(JOY_AXIS_LEFT_X, 1.0),
	])
	serialized_actions[String(&"ship_pitch_up")] = _ensure_action(&"ship_pitch_up", 0.2, [
		_key_event(KEY_UP),
		_joypad_motion_event(JOY_AXIS_RIGHT_Y, -1.0),
	])
	serialized_actions[String(&"ship_pitch_down")] = _ensure_action(&"ship_pitch_down", 0.2, [
		_key_event(KEY_DOWN),
		_joypad_motion_event(JOY_AXIS_RIGHT_Y, 1.0),
	])
	serialized_actions[String(&"ship_airbrake_left")] = _ensure_action(&"ship_airbrake_left", 0.2, [
		_key_event(KEY_Q),
		_joypad_button_event(JOY_BUTTON_LEFT_SHOULDER),
		_joypad_motion_event(JOY_AXIS_TRIGGER_LEFT, 1.0),
	])
	serialized_actions[String(&"ship_airbrake_right")] = _ensure_action(&"ship_airbrake_right", 0.2, [
		_key_event(KEY_E),
		_joypad_button_event(JOY_BUTTON_RIGHT_SHOULDER),
	])
	serialized_actions[String(&"ship_reset")] = _ensure_action(&"ship_reset", 0.5, [
		_key_event(KEY_R),
		_joypad_button_event(JOY_BUTTON_BACK),
	])
	serialized_actions[String(&"ship_fire")] = _ensure_action(&"ship_fire", 0.5, [
		_key_event(KEY_SPACE),
		_joypad_button_event(JOY_BUTTON_X), # west face button: Xbox "X" / PlayStation "Square"
	])
	return serialized_actions


func _ensure_action(action_name: StringName, deadzone: float, events: Array[InputEvent]) -> Dictionary:
	var setting_path := "input/%s" % String(action_name)
	var serialized_action := {
		"deadzone": deadzone,
		"events": events,
	}
	ProjectSettings.set_setting(setting_path, serialized_action)

	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)
	else:
		InputMap.action_set_deadzone(action_name, deadzone)

	for existing_event in InputMap.action_get_events(action_name):
		InputMap.action_erase_event(action_name, existing_event)

	for event in events:
		InputMap.action_add_event(action_name, event)

	return serialized_action


func _dump_serialized_actions(serialized_actions: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for action_name in serialized_actions.keys():
		cfg.set_value("input", action_name, serialized_actions[action_name])
	cfg.save("res://tools/input_dump.cfg")


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	return event


func _ui_key_event(keycode: Key, shift_pressed: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.keycode = keycode
	event.shift_pressed = shift_pressed
	return event


func _joypad_motion_event(axis: JoyAxis, axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = axis_value
	return event


func _joypad_button_event(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button_index
	return event