extends Node

## Autoload: persisted user options (src/wipeout/main_menu.c's OPTIONS pages),
## saved to user://settings.cfg and re-applied on startup.

const SETTINGS_PATH := "user://settings.cfg"

## Default lap records per circuit, ported from src/wipeout/game.c's
## `save.highscores[class][circuit][tab].lap_record` (both highscore tabs share
## the same starting record there, so a single value per class is enough).
## Circuits with no shipped record use game.c's 3599.99 "unbeatable" stub.
const NO_LAP_RECORD := 3599.99
const DEFAULT_LAP_RECORDS: Dictionary = {
	# circuit -> [venom, rapier]
	"ALTIMA VII": [85.83, 69.50],
	"KARBONIS V": [55.33, 47.33],
	"TERRAMAX": [57.50, 47.83],
	"KORODERA": [85.17, 76.75],
	"ARRIDOS IV": [80.17, 65.75],
	"SILVERSTREAM": [61.67, 59.23],
	"FIRESTAR": [63.83, 55.00],
}

## Actions from project.godot's [input] section that OptionsControlsMenu
## allows rebinding, mirroring main_menu.c's page_options_controls_init.
const REBINDABLE_ACTIONS: Array[String] = [
	"ship_thrust", "ship_reverse", "ship_steer_left", "ship_steer_right",
	"ship_pitch_up", "ship_pitch_down", "ship_airbrake_left", "ship_airbrake_right",
	"ship_reset",
]

var fullscreen: bool = false
var vsync: bool = true
var show_fps: bool = false # save.draw_stats == DRAW_STATS_FPS, read by the in-race HUD
var master_volume: float = 1.0

## action -> {"key": physical_keycode, "pad": joypad_button_index}; -1 = unset.
var key_binds: Dictionary = {}

## Beaten lap records only, keyed "<circuit>|<class>|<tab>"; anything absent
## falls back to DEFAULT_LAP_RECORDS.
var lap_records: Dictionary = {}


func _ready() -> void:
	_load()
	apply_video()
	apply_audio()
	apply_all_key_binds()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	for action in REBINDABLE_ACTIONS:
		var key_code: int = cfg.get_value("controls", action + "_key", -1)
		var pad_index: int = cfg.get_value("controls", action + "_pad", -1)
		if key_code != -1 or pad_index != -1:
			key_binds[action] = {"key": key_code, "pad": pad_index}
	if cfg.has_section("records"):
		for key in cfg.get_section_keys("records"):
			lap_records[key] = float(cfg.get_value("records", key, NO_LAP_RECORD))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "master_volume", master_volume)
	for action in REBINDABLE_ACTIONS:
		var bind: Dictionary = key_binds.get(action, {})
		cfg.set_value("controls", action + "_key", bind.get("key", -1))
		cfg.set_value("controls", action + "_pad", bind.get("pad", -1))
	for key in lap_records:
		cfg.set_value("records", str(key), float(lap_records[key]))
	cfg.save(SETTINGS_PATH)


func _lap_record_key(circuit: String, race_class: int, time_trial: bool) -> String:
	return "%s|%d|%d" % [circuit.to_upper(), race_class, 1 if time_trial else 0]


## save.highscores[class][circuit][tab].lap_record
func get_lap_record(circuit: String, race_class: int, time_trial: bool) -> float:
	var key := _lap_record_key(circuit, race_class, time_trial)
	if lap_records.has(key):
		return float(lap_records[key])
	var defaults: Array = DEFAULT_LAP_RECORDS.get(circuit.to_upper(), [])
	var index := clampi(race_class, 0, defaults.size() - 1)
	if defaults.is_empty():
		return NO_LAP_RECORD
	return float(defaults[index])


## race_end()'s `if (g.best_lap < hs->lap_record)` branch. Returns true (and
## persists) when the lap beat the standing record.
func submit_lap_record(circuit: String, race_class: int, time_trial: bool, time: float) -> bool:
	if time <= 0.0 or time >= get_lap_record(circuit, race_class, time_trial):
		return false
	lap_records[_lap_record_key(circuit, race_class, time_trial)] = time
	save()
	return true


func apply_video() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func apply_audio() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(master_volume, 0.0001)))


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_video()
	save()


func set_vsync(value: bool) -> void:
	vsync = value
	apply_video()
	save()


func set_show_fps(value: bool) -> void:
	show_fps = value
	save()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save()


func rebind_key(action: String, physical_keycode: int) -> void:
	_erase_events_of_type(action, InputEventKey)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, event)

	var bind: Dictionary = key_binds.get(action, {"key": -1, "pad": -1})
	bind["key"] = physical_keycode
	key_binds[action] = bind
	save()


func rebind_pad(action: String, button_index: int) -> void:
	_erase_events_of_type(action, InputEventJoypadButton)
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action, event)

	var bind: Dictionary = key_binds.get(action, {"key": -1, "pad": -1})
	bind["pad"] = button_index
	key_binds[action] = bind
	save()


func get_key_display_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	return "---"


func get_pad_display_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return "PAD %d" % (event as InputEventJoypadButton).button_index
	return "---"


func apply_all_key_binds() -> void:
	for action in key_binds:
		var bind: Dictionary = key_binds[action]
		if bind.get("key", -1) != -1:
			_erase_events_of_type(action, InputEventKey)
			var key_event := InputEventKey.new()
			key_event.physical_keycode = bind["key"]
			InputMap.action_add_event(action, key_event)
		if bind.get("pad", -1) != -1:
			_erase_events_of_type(action, InputEventJoypadButton)
			var pad_event := InputEventJoypadButton.new()
			pad_event.button_index = bind["pad"]
			InputMap.action_add_event(action, pad_event)


func _erase_events_of_type(action: String, type: Variant) -> void:
	for event in InputMap.action_get_events(action):
		if is_instance_of(event, type):
			InputMap.action_erase_event(action, event)
