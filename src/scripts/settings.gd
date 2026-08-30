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

## Default top-5 race-time boards, ported verbatim from game.c's
## save.highscores[class][circuit][tab].entries. Keyed like DEFAULT_LAP_RECORDS
## but flat (there is no single-value shortcut here): _lap_record_key()'s
## "<CIRCUIT>|<class>|<tab>" format, reused for these too.
const NUM_HIGHSCORES := 5 # game.h NUM_HIGHSCORES
const UNBEATABLE_RECORD := 3599.99 # game.c's "NUL" stub: 59:99.9
const DEFAULT_UNBEATABLE_RECORDS: Array = [
	{"name": "NUL", "time": UNBEATABLE_RECORD}, {"name": "NUL", "time": UNBEATABLE_RECORD},
	{"name": "NUL", "time": UNBEATABLE_RECORD}, {"name": "NUL", "time": UNBEATABLE_RECORD},
	{"name": "NUL", "time": UNBEATABLE_RECORD},
]
const DEFAULT_RACE_RECORDS: Dictionary = {
	"ALTIMA VII|0|0": [{"name": "WIP", "time": 254.50}, {"name": "EOU", "time": 271.17}, {"name": "TPC", "time": 289.50}, {"name": "NOT", "time": 294.50}, {"name": "PSX", "time": 314.50}],
	"ALTIMA VII|0|1": [{"name": "MVE", "time": 254.50}, {"name": "ALM", "time": 271.17}, {"name": "POL", "time": 289.50}, {"name": "NIK", "time": 294.50}, {"name": "DAR", "time": 314.50}],
	"KARBONIS V|0|0": [{"name": "AJY", "time": 159.33}, {"name": "AJS", "time": 172.67}, {"name": "DLS", "time": 191.00}, {"name": "MAK", "time": 207.67}, {"name": "JED", "time": 219.33}],
	"KARBONIS V|0|1": [{"name": "DAR", "time": 159.33}, {"name": "STU", "time": 172.67}, {"name": "MOC", "time": 191.00}, {"name": "DOM", "time": 207.67}, {"name": "NIK", "time": 219.33}],
	"TERRAMAX|0|0": [{"name": "JD", "time": 171.00}, {"name": "AJC", "time": 189.33}, {"name": "MSA", "time": 202.67}, {"name": "SD", "time": 219.33}, {"name": "TIM", "time": 232.67}],
	"TERRAMAX|0|1": [{"name": "PHO", "time": 171.00}, {"name": "ENI", "time": 189.33}, {"name": "XR", "time": 202.67}, {"name": "ISI", "time": 219.33}, {"name": "NG", "time": 232.67}],
	"KORODERA|0|0": [{"name": "POL", "time": 251.33}, {"name": "DAR", "time": 263.00}, {"name": "JAS", "time": 283.00}, {"name": "ROB", "time": 294.67}, {"name": "DJR", "time": 314.82}],
	"KORODERA|0|1": [{"name": "DOM", "time": 251.33}, {"name": "DJR", "time": 263.00}, {"name": "MPI", "time": 283.00}, {"name": "GOC", "time": 294.67}, {"name": "SUE", "time": 314.82}],
	"ARRIDOS IV|0|0": [{"name": "NIK", "time": 236.17}, {"name": "SAL", "time": 253.17}, {"name": "DOM", "time": 262.33}, {"name": "LG", "time": 282.67}, {"name": "LNK", "time": 298.17}],
	"ARRIDOS IV|0|1": [{"name": "NIK", "time": 236.17}, {"name": "ROB", "time": 253.17}, {"name": "AM", "time": 262.33}, {"name": "JAS", "time": 282.67}, {"name": "DAR", "time": 298.17}],
	"SILVERSTREAM|0|0": [{"name": "HAN", "time": 182.33}, {"name": "PER", "time": 196.33}, {"name": "FEC", "time": 214.83}, {"name": "TPI", "time": 228.83}, {"name": "ZZA", "time": 244.33}],
	"SILVERSTREAM|0|1": [{"name": "FC", "time": 182.33}, {"name": "SUE", "time": 196.33}, {"name": "ROB", "time": 214.83}, {"name": "JEN", "time": 228.83}, {"name": "NT", "time": 244.33}],
	"FIRESTAR|0|0": [{"name": "CAN", "time": 195.40}, {"name": "WEH", "time": 209.23}, {"name": "AVE", "time": 227.90}, {"name": "ABO", "time": 239.90}, {"name": "NUS", "time": 240.73}],
	"FIRESTAR|0|1": [{"name": "DJR", "time": 195.40}, {"name": "NIK", "time": 209.23}, {"name": "JAS", "time": 227.90}, {"name": "NCW", "time": 239.90}, {"name": "LOU", "time": 240.73}],
	"ALTIMA VII|1|0": [{"name": "AJY", "time": 200.67}, {"name": "DLS", "time": 213.50}, {"name": "AJS", "time": 228.67}, {"name": "MAK", "time": 247.67}, {"name": "JED", "time": 263.00}],
	"ALTIMA VII|1|1": [{"name": "NCW", "time": 200.67}, {"name": "LEE", "time": 213.50}, {"name": "STU", "time": 228.67}, {"name": "JAS", "time": 247.67}, {"name": "ROB", "time": 263.00}],
	"KARBONIS V|1|0": [{"name": "BOR", "time": 134.58}, {"name": "ING", "time": 147.00}, {"name": "HIS", "time": 162.25}, {"name": "COR", "time": 183.08}, {"name": "ES", "time": 198.25}],
	"KARBONIS V|1|1": [{"name": "NIK", "time": 134.58}, {"name": "POL", "time": 147.00}, {"name": "DAR", "time": 162.25}, {"name": "STU", "time": 183.08}, {"name": "ROB", "time": 198.25}],
	"TERRAMAX|1|0": [{"name": "AJS", "time": 142.08}, {"name": "DLS", "time": 159.42}, {"name": "MAK", "time": 178.08}, {"name": "JED", "time": 190.25}, {"name": "AJY", "time": 206.58}],
	"TERRAMAX|1|1": [{"name": "POL", "time": 142.08}, {"name": "JIM", "time": 159.42}, {"name": "TIM", "time": 178.08}, {"name": "MOC", "time": 190.25}, {"name": "PC", "time": 206.58}],
	"KORODERA|1|0": [{"name": "DLS", "time": 224.17}, {"name": "DJR", "time": 237.00}, {"name": "LEE", "time": 257.50}, {"name": "MOC", "time": 272.83}, {"name": "MPI", "time": 285.17}],
	"KORODERA|1|1": [{"name": "TIM", "time": 224.17}, {"name": "JIM", "time": 237.00}, {"name": "NIK", "time": 257.50}, {"name": "JAS", "time": 272.83}, {"name": "LG", "time": 285.17}],
	"ARRIDOS IV|1|0": [{"name": "MAK", "time": 191.00}, {"name": "STU", "time": 203.67}, {"name": "JAS", "time": 221.83}, {"name": "ROB", "time": 239.00}, {"name": "DOM", "time": 254.50}],
	"ARRIDOS IV|1|1": [{"name": "LG", "time": 191.00}, {"name": "LOU", "time": 203.67}, {"name": "JIM", "time": 221.83}, {"name": "HAN", "time": 239.00}, {"name": "NT", "time": 254.50}],
	"SILVERSTREAM|1|0": [{"name": "JED", "time": 156.67}, {"name": "NCW", "time": 170.33}, {"name": "LOU", "time": 188.83}, {"name": "DAR", "time": 201.00}, {"name": "POL", "time": 221.50}],
	"SILVERSTREAM|1|1": [{"name": "STU", "time": 156.67}, {"name": "DAV", "time": 170.33}, {"name": "DOM", "time": 188.83}, {"name": "MOR", "time": 201.00}, {"name": "GAN", "time": 221.50}],
	"FIRESTAR|1|0": [{"name": "PC", "time": 162.42}, {"name": "POL", "time": 179.58}, {"name": "DAR", "time": 194.75}, {"name": "DAR", "time": 208.92}, {"name": "MSC", "time": 224.58}],
	"FIRESTAR|1|1": [{"name": "THA", "time": 162.42}, {"name": "NKS", "time": 179.58}, {"name": "FOR", "time": 194.75}, {"name": "PLA", "time": 208.92}, {"name": "YIN", "time": 224.58}],
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

## save.has_rapier_class / save.has_bonus_circuits: campaign unlocks, flipped by
## Championship.complete_championship() (race.c's race_next()). The shipped C
## defaults are true/true "for testing"; a fresh save here starts locked, the
## documented intent.
var has_rapier_class: bool = false
var has_bonus_circuits: bool = false

## action -> {"key": physical_keycode, "pad": joypad_button_index}; -1 = unset.
var key_binds: Dictionary = {}

## Beaten lap records only, keyed "<circuit>|<class>|<tab>"; anything absent
## falls back to DEFAULT_LAP_RECORDS.
var lap_records: Dictionary = {}

## save.highscores[class][circuit][tab].entries, once altered from
## DEFAULT_RACE_RECORDS by submit_race_record(); same key format.
var race_records: Dictionary = {}

## save.highscores_name: the last name entered on the hall-of-fame page,
## offered as the starting point next time (ingame_menus.c's
## page_hall_of_fame_init()).
var highscores_name: String = ""


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
	has_rapier_class = cfg.get_value("progress", "has_rapier_class", has_rapier_class)
	has_bonus_circuits = cfg.get_value("progress", "has_bonus_circuits", has_bonus_circuits)
	highscores_name = cfg.get_value("progress", "highscores_name", highscores_name)
	for action in REBINDABLE_ACTIONS:
		var key_code: int = cfg.get_value("controls", action + "_key", -1)
		var pad_index: int = cfg.get_value("controls", action + "_pad", -1)
		if key_code != -1 or pad_index != -1:
			key_binds[action] = {"key": key_code, "pad": pad_index}
	if cfg.has_section("records"):
		for key in cfg.get_section_keys("records"):
			lap_records[key] = float(cfg.get_value("records", key, NO_LAP_RECORD))
	if cfg.has_section("race_records"):
		for key in cfg.get_section_keys("race_records"):
			race_records[key] = cfg.get_value("race_records", key, DEFAULT_UNBEATABLE_RECORDS)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("progress", "has_rapier_class", has_rapier_class)
	cfg.set_value("progress", "has_bonus_circuits", has_bonus_circuits)
	cfg.set_value("progress", "highscores_name", highscores_name)
	for action in REBINDABLE_ACTIONS:
		var bind: Dictionary = key_binds.get(action, {})
		cfg.set_value("controls", action + "_key", bind.get("key", -1))
		cfg.set_value("controls", action + "_pad", bind.get("pad", -1))
	for key in lap_records:
		cfg.set_value("records", str(key), float(lap_records[key]))
	for key in race_records:
		cfg.set_value("race_records", str(key), race_records[key])
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


## save.highscores[class][circuit][tab].entries: the top NUM_HIGHSCORES race
## times, fastest first. A fresh copy every call, safe for the caller to
## splice a pending entry into without touching the stored/default table.
func get_race_records(circuit: String, race_class: int, time_trial: bool) -> Array:
	var key := _lap_record_key(circuit, race_class, time_trial)
	if race_records.has(key):
		return (race_records[key] as Array).duplicate(true)
	var defaults: Array = DEFAULT_RACE_RECORDS.get(key, DEFAULT_UNBEATABLE_RECORDS)
	return defaults.duplicate(true)


## race_end()'s `if (g.race_time < hs->entries[i].time) { is_new_race_record = true; break; }`:
## true when `time` would place in the top NUM_HIGHSCORES (entries are always
## kept sorted fastest-first, so beating the slowest entry is sufficient).
func is_new_race_record(circuit: String, race_class: int, time_trial: bool, time: float) -> bool:
	var entries := get_race_records(circuit, race_class, time_trial)
	if entries.is_empty():
		return false
	return time < float(entries[-1]["time"])


## page_hall_of_fame_draw()'s hs_entry_complete branch: sorted insert of
## {name, time} into the top NUM_HIGHSCORES, dropping the slowest entry.
func submit_race_record(circuit: String, race_class: int, time_trial: bool, entry_name: String, time: float) -> void:
	var entries := get_race_records(circuit, race_class, time_trial)
	for i in entries.size():
		if time < float(entries[i]["time"]):
			entries.insert(i, {"name": entry_name, "time": time})
			entries.resize(NUM_HIGHSCORES)
			race_records[_lap_record_key(circuit, race_class, time_trial)] = entries
			save()
			return


func set_highscores_name(value: String) -> void:
	highscores_name = value
	save()


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


func set_has_rapier_class(value: bool) -> void:
	has_rapier_class = value
	save()


func set_has_bonus_circuits(value: bool) -> void:
	has_bonus_circuits = value
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
	event.button_index = button_index as JoyButton
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
