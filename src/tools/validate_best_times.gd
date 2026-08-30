extends SceneTree

## Headless check of the BEST TIMES screen, ported from main_menu.c's
## page_options_highscores_init / page_options_highscores_viewer_init /
## page_options_highscores_viewer_input_handler: the two tabs push the right
## viewer title, the viewer cycles class and circuit with wrap-around, and the
## table it reads is the same save.highscores data the hall of fame writes.
##
## Autoload names are not compile-time identifiers in --script mode, so the
## live autoloads are fetched off the root instead of being preloaded.

const SCENE := "res://scenes/OptionsBestTimesMenu.tscn"

var _failures: Array[String] = []
var _frames := 0
var _menu: Control = null
var _settings: Node = null
var _race_setup: Node = null
var _track_selection: Node = null


func _initialize() -> void:
	_settings = root.get_node_or_null("Settings")
	_race_setup = root.get_node_or_null("RaceSetup")
	_track_selection = root.get_node_or_null("TrackSelection")
	if _settings == null or _race_setup == null or _track_selection == null:
		push_error("validate_best_times: autoloads missing")
		quit(1)
		return
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("validate_best_times: failed to load OptionsBestTimesMenu")
		quit(1)
		return
	_menu = packed.instantiate() as Control
	root.add_child(_menu)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	_check_tab_page()
	_check_viewer_titles()
	_check_navigation_wraps()
	_check_table_matches_saved_records()

	if _failures.is_empty():
		print("validate_best_times: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_best_times: %s" % failure)
		quit(1)
	return true


## page_options_highscores_init(): the tab picker, reset to Venom / Altima VII.
func _check_tab_page() -> void:
	var page = _menu.current_page()
	_check("opens on the tab picker", page != null and page.title == "VIEW BEST TIMES")
	_check("viewer starts on the Venom class", _menu._class_index == _race_setup.RACE_CLASS_VENOM)
	_check("viewer starts on the first circuit (ALTIMA VII)", _menu._circuit_index == 0)
	_check("first circuit really is ALTIMA VII", _track_selection.CIRCUIT_ORDER[0] == "ALTIMA VII")


## page_options_highscores_viewer_init() titles the page from the tab, and
## menu_pop() has to get back out of it.
func _check_viewer_titles() -> void:
	_menu._open_viewer(_menu.TAB_TIME_TRIAL)
	var page = _menu.current_page()
	_check("time trial tab opens BEST TIME TRIAL TIMES", page != null and page.title == "BEST TIME TRIAL TIMES")
	_check("the viewer is pushed on top of the tab picker", _menu.page_depth() == 2)
	_menu.pop_page()
	_check("cancel pops back to the tab picker", _menu.page_depth() == 1)

	_menu._open_viewer(_menu.TAB_RACE)
	page = _menu.current_page()
	_check("race tab opens BEST RACE TIMES", page != null and page.title == "BEST RACE TIMES")
	_menu.pop_page()


## page_options_highscores_viewer_input_handler()'s wrap_around() on both axes.
func _check_navigation_wraps() -> void:
	_menu._open_viewer(_menu.TAB_RACE)
	var classes: int = _race_setup.RACE_CLASSES.size()
	var circuits: int = _track_selection.CIRCUIT_ORDER.size()

	_menu._class_index = 0
	_menu._circuit_index = 0

	_press("ui_down")
	_check("down steps to the next class", _menu._class_index == 1)
	_press("ui_down")
	_check("class wraps back around past the last one", _menu._class_index == 0)
	_press("ui_up")
	_check("up wraps backwards onto the last class", _menu._class_index == classes - 1)

	_menu._class_index = 0
	_press("ui_right")
	_check("right steps to the next circuit", _menu._circuit_index == 1)
	_press("ui_left")
	_press("ui_left")
	_check("left wraps backwards onto the last circuit", _menu._circuit_index == circuits - 1)
	_check("class is untouched by circuit navigation", _menu._class_index == 0)
	_menu.pop_page()


## The viewer must read the same table the hall of fame writes, per class and
## per tab -- not a single shared list.
func _check_table_matches_saved_records() -> void:
	var altima_venom_race: Array = _settings.get_race_records("ALTIMA VII", _race_setup.RACE_CLASS_VENOM, false)
	var altima_venom_tt: Array = _settings.get_race_records("ALTIMA VII", _race_setup.RACE_CLASS_VENOM, true)
	var altima_rapier_race: Array = _settings.get_race_records("ALTIMA VII", _race_setup.RACE_CLASS_RAPIER, false)

	_check("shipped board has NUM_HIGHSCORES entries", altima_venom_race.size() == _settings.NUM_HIGHSCORES)
	_check("race and time trial boards are distinct", str(altima_venom_race[0]["name"]) != str(altima_venom_tt[0]["name"]))
	_check("venom and rapier boards are distinct", str(altima_venom_race[0]["name"]) != str(altima_rapier_race[0]["name"]))

	# What the viewer actually points at has to follow all three of tab, class
	# and circuit -- reading one fixed board would still draw a plausible table.
	_menu._open_viewer(_menu.TAB_TIME_TRIAL)
	_menu._class_index = _race_setup.RACE_CLASS_VENOM
	_menu._circuit_index = 0
	_check("viewer resolves the circuit it is pointed at", _menu.current_circuit() == "ALTIMA VII")
	_check("time trial tab reads the time trial board", str(_menu.current_entries()[0]["name"]) == str(altima_venom_tt[0]["name"]))

	_menu.pop_page()
	_menu._open_viewer(_menu.TAB_RACE)
	_menu._class_index = _race_setup.RACE_CLASS_VENOM
	_menu._circuit_index = 0
	_check("race tab reads the race board", str(_menu.current_entries()[0]["name"]) == str(altima_venom_race[0]["name"]))

	_menu._class_index = _race_setup.RACE_CLASS_RAPIER
	_check("switching class switches board", str(_menu.current_entries()[0]["name"]) == str(altima_rapier_race[0]["name"]))
	_check("lap record follows the same selection", is_equal_approx(_menu.current_lap_record(), _settings.get_lap_record("ALTIMA VII", _race_setup.RACE_CLASS_RAPIER, false)))

	_menu._circuit_index = 1
	_check("switching circuit switches board", _menu.current_circuit() == _track_selection.CIRCUIT_ORDER[1])
	_menu.pop_page()

	# Every circuit the viewer can scroll to must resolve to a real board and
	# lap record, or scrolling onto it would draw an empty table.
	for circuit in _track_selection.CIRCUIT_ORDER:
		for race_class in [_race_setup.RACE_CLASS_VENOM, _race_setup.RACE_CLASS_RAPIER]:
			for time_trial in [false, true]:
				var board: Array = _settings.get_race_records(circuit, race_class, time_trial)
				_check("%s class %d tab %s has a full board" % [circuit, race_class, time_trial], board.size() == _settings.NUM_HIGHSCORES)
				var record: float = _settings.get_lap_record(circuit, race_class, time_trial)
				_check("%s class %d tab %s has a lap record" % [circuit, race_class, time_trial], record > 0.0)


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_menu._unhandled_input(event)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)
