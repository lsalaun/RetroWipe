extends SceneTree

## Headless check of the hall-of-fame port added to match
## src/wipeout/ingame_menus.c's page_hall_of_fame_draw()/hall_of_fame_draw_name_entry():
## Settings' top-5 race-time board (default data, is_new_race_record's peek,
## submit_race_record()'s sorted insert-with-truncate) and race_results.gd's
## HALL_OF_FAME stage (name-entry wheel bounds/confirm, and both the
## single-race and championship continuations once a name is submitted).
##
## Autoload names are not compile-time identifiers in --script mode, so the
## live autoloads are fetched off the root instead of being preloaded.

const RACE_HUD_SCENE := "res://scenes/RaceHud.tscn"
const SCRATCH_CIRCUIT := "ALTIMA VII" # restored below, never left mutated on disk

var _failures: Array[String] = []
var _frames := 0

var _settings: Node = null
var _race_setup: Node = null
var _championship: Node = null
var _track_selection: Node = null
var _results: Control = null

## Restored at the end so running this validator never leaves the developer's
## real user://settings.cfg with a scratch entry in it.
var _orig_race_records: Dictionary = {}
var _orig_highscores_name: String = ""
var _orig_has_bonus_circuits: bool = false
## _check_championship_flow() runs a campaign to its end, which unlocks the
## Rapier class and writes it straight to user://settings.cfg -- without this
## the validator would hand the developer a progression unlock they never
## earned, and leave every later run starting from a different state.
var _orig_has_rapier_class: bool = false


func _initialize() -> void:
	_settings = root.get_node_or_null("Settings")
	_race_setup = root.get_node_or_null("RaceSetup")
	_championship = root.get_node_or_null("Championship")
	_track_selection = root.get_node_or_null("TrackSelection")
	if _settings == null or _race_setup == null or _championship == null or _track_selection == null:
		push_error("validate_hall_of_fame: autoloads missing")
		quit(1)
		return

	# RaceField.track_display_name() (what race_results.gd keys the board on)
	# reads this; unset, it falls back to TERRAMAX. Pin it to SCRATCH_CIRCUIT
	# so the flow checks below and the pure Settings checks agree on a circuit
	# without this script ever referencing the RaceField class itself --
	# autoload globals like TrackSelection are not compile-time identifiers in
	# --script mode, and RaceField's track_display_name() uses TrackSelection
	# as one, so merely naming RaceField here would fail to compile.
	_track_selection.selected_track_scene = load("res://scenes/Track02.tscn")

	var packed := load(RACE_HUD_SCENE) as PackedScene
	if packed == null:
		push_error("validate_hall_of_fame: failed to load RaceHud")
		quit(1)
		return
	var hud := packed.instantiate()
	root.add_child(hud)
	_results = hud.get_node_or_null("Results") as Control


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	_orig_race_records = _settings.race_records.duplicate(true)
	_orig_highscores_name = _settings.highscores_name
	_orig_has_bonus_circuits = _settings.has_bonus_circuits
	_orig_has_rapier_class = _settings.has_rapier_class

	_check_default_records()
	_check_is_new_record()
	_check_submit_record()
	_check_name_entry_bounds()
	_check_single_race_flow()
	_check_championship_flow()

	_settings.race_records = _orig_race_records
	_settings.highscores_name = _orig_highscores_name
	_settings.has_bonus_circuits = _orig_has_bonus_circuits
	_settings.has_rapier_class = _orig_has_rapier_class
	_settings.save()

	if _failures.is_empty():
		print("validate_hall_of_fame: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_hall_of_fame: %s" % failure)
		quit(1)
	return true


## game.c's save.highscores[VENOM][ALTIMA_VII][RACE/TIME_TRIAL].entries.
func _check_default_records() -> void:
	var race: Array = _settings.get_race_records(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false)
	_check("default race board has 5 entries", race.size() == 5)
	_check("default race board fastest is WIP 254.50", str(race[0]["name"]) == "WIP" and is_equal_approx(float(race[0]["time"]), 254.50))
	_check("default race board slowest is PSX 314.50", str(race[-1]["name"]) == "PSX" and is_equal_approx(float(race[-1]["time"]), 314.50))

	var tt: Array = _settings.get_race_records(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, true)
	_check("time trial board is distinct from race board", str(tt[0]["name"]) == "MVE")

	var rapier: Array = _settings.get_race_records(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_RAPIER, false)
	_check("rapier board is distinct from venom", str(rapier[0]["name"]) == "AJY")

	var unknown: Array = _settings.get_race_records("NOT A CIRCUIT", _race_setup.RACE_CLASS_VENOM, false)
	_check("unknown circuit falls back to the NUL/unbeatable stub", str(unknown[0]["name"]) == "NUL" and is_equal_approx(float(unknown[0]["time"]), _settings.UNBEATABLE_RECORD))


## race_end()'s `if (g.race_time < hs->entries[i].time) is_new_race_record = true`.
func _check_is_new_record() -> void:
	_check(
		"beating the slowest entry is a new record",
		_settings.is_new_race_record(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false, 300.0)
	)
	_check(
		"a time slower than everyone is not a new record",
		not _settings.is_new_race_record(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false, 999.0)
	)


## page_hall_of_fame_draw()'s hs_entry_complete branch: sorted insert, then
## drop the slowest entry so the board stays at NUM_HIGHSCORES.
func _check_submit_record() -> void:
	_settings.race_records.erase(_settings._lap_record_key(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false))
	_settings.submit_race_record(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false, "ZZZ", 100.0)
	var after: Array = _settings.get_race_records(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false)
	_check("submitting the fastest time takes 1st place", str(after[0]["name"]) == "ZZZ" and is_equal_approx(float(after[0]["time"]), 100.0))
	_check("the board stays at 5 entries (slowest dropped)", after.size() == 5)
	_check("the previous slowest (PSX) fell off the board", str(after[-1]["name"]) != "PSX")

	_settings.submit_race_record(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false, "MID", 280.0)
	var mid: Array = _settings.get_race_records(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false)
	var mid_index := -1
	for i in mid.size():
		if str(mid[i]["name"]) == "MID":
			mid_index = i
	_check("a mid-pack time inserts in sorted order, not at the front", mid_index == 3)


## hall_of_fame_draw_name_entry()'s c_first/c_last: END unreachable on an empty
## name, letters unreachable once 3 characters are entered.
func _check_name_entry_bounds() -> void:
	if _results == null:
		_check("RaceHud has no Results node", false)
		return
	_results._hof_name = ""
	var empty_bounds: Vector2i = _results._hof_bounds()
	_check("an empty name excludes END", empty_bounds.y == _results.HOF_END_INDEX)

	_results._hof_name = "ABC"
	var full_bounds: Vector2i = _results._hof_bounds()
	_check("a full (3-char) name only reaches DEL/END", full_bounds.x == _results.HOF_DEL_INDEX and full_bounds.y == _results.HOF_END_INDEX + 1)

	_check("_wrap cycles past the end back to the start", _results._wrap(_results.HOF_END_INDEX + 1, 0, _results.HOF_END_INDEX + 1) == 0)
	_check("_wrap cycles past the start back to the end", _results._wrap(-1, 0, _results.HOF_END_INDEX + 1) == _results.HOF_END_INDEX)


## button_race_stats_continue() -> HALL OF FAME -> _hof_finish(): typing a name
## and hitting END submits the record and falls back to the ordinary
## restart/quit choice (single race / time trial never call race_next()).
func _check_single_race_flow() -> void:
	if _results == null:
		return
	_race_setup.race_type = _race_setup.RACE_TYPE_SINGLE
	_race_setup.pilot_name = ""
	_settings.race_records.erase(_settings._lap_record_key(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false))

	_results._stats = {"qualified": true, "race_time": 111.0, "is_new_race_record": true, "lap_times": [], "position": 1}
	_results._show_stage(_results.Stage.HALL_OF_FAME)
	_check("entering hall of fame starts from the remembered name", _results._hof_name == _settings.highscores_name)

	_results._hof_name = ""
	_results._hof_char_index = 0 # 'A'
	_results._hof_confirm()
	_results._hof_char_index = 4 # 'E'
	_results._hof_confirm()
	_results._hof_char_index = _results.HOF_END_INDEX
	_results._hof_confirm()

	_check("typed name reads AE", _results._hof_name == "AE")
	_check("finishing submits the record", _settings.get_race_records(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false)[0]["name"] == "AE")
	_check("the name is remembered for next time", _settings.highscores_name == "AE")
	_check("single race falls back to RESTART_OR_QUIT, not the campaign", _results._stage == _results.Stage.RESTART_OR_QUIT)


## The same finish, but for a championship race: _hof_finish() must call
## _continue_championship() instead of falling back to a restart/quit choice.
## circuit_index is parked one race from completion so _continue_championship()
## resolves to CONGRATULATIONS (a stage swap only) rather than advance_circuit()
## + TrackSelection.start_race() -- the latter changes the active scene, not
## something to trigger from this bare validator SceneTree.
func _check_championship_flow() -> void:
	if _results == null:
		return
	_race_setup.race_type = _race_setup.RACE_TYPE_CHAMPIONSHIP
	_settings.has_bonus_circuits = false # so the completion gate below is NUM_NON_BONUS_CIRCUITS, deterministically
	_championship.reset()
	_championship.circuit_index = _championship.NUM_NON_BONUS_CIRCUITS - 1 # about to finish the last non-bonus circuit
	_settings.race_records.erase(_settings._lap_record_key(SCRATCH_CIRCUIT, _race_setup.RACE_CLASS_VENOM, false))

	_results._stats = {"qualified": true, "race_time": 90.0, "is_new_race_record": true, "lap_times": [], "position": 1}
	_results._show_stage(_results.Stage.HALL_OF_FAME)
	_results._hof_name = ""
	_results._hof_char_index = 25 # 'Z'
	_results._hof_confirm()
	_results._hof_char_index = _results.HOF_END_INDEX
	_results._hof_confirm()

	_check("championship does not fall back to RESTART_OR_QUIT after hall of fame", _results._stage != _results.Stage.RESTART_OR_QUIT)
	_check("championship reaches CONGRATULATIONS once the campaign completes", _results._stage == _results.Stage.CONGRATULATIONS)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)
