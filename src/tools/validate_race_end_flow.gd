extends SceneTree

## Headless check of the end-of-race chain, driven through the real race rather
## than by setting a stage directly: race.c race_end() -> the RACE STATISTICS
## page -> ingame_menus.c's button_race_stats_continue() /
## button_race_points_continue() / button_championship_points_continue() ladder,
## and specifically whether the hall of fame is reached when it should be.
##
## validate_hall_of_fame.gd covers that page's own behaviour but calls
## _show_stage(HALL_OF_FAME) itself, so a break in RaceDirector's
## is_new_race_record or in _on_stats_continue()'s branching would not show up
## there. This runs the actual chain: _end_race(), then the CONTINUE button.
##
## RaceDirector._end_race() persists a beaten lap record, so the save file is
## backed up and restored around the whole run -- three 60 s laps beat every
## shipped record.
##
## Autoload names are not compile-time identifiers in --script mode, so the live
## autoloads are fetched off the root instead of being preloaded, and
## RaceDirector is referenced dynamically for the same reason
## validate_race_logic.gd does: static typing would pull race_director.gd in
## while this script is compiled, before the autoloads it uses exist.

const CIRCUIT := "ALTIMA VII"

## RaceDirector.NUM_LAPS / RaceDirector.State.RACING.
const NUM_LAPS := 3
const STATE_RACING := 1

var _failures: Array[String] = []
var _frames := 0
var _main: Node3D = null
var _director: Node = null
var _results: Control = null

var _settings: Node = null
var _race_setup: Node = null
var _track_selection: Node = null
var _championship: Node = null

var _orig_lap_records: Dictionary = {}
var _orig_race_records: Dictionary = {}
## _check_championship_completed() runs a campaign out, which unlocks the Rapier
## class on disk (race_next()'s save.has_rapier_class = true).
var _orig_has_rapier_class: bool = false
var _orig_has_bonus_circuits: bool = false


func _initialize() -> void:
	_settings = root.get_node_or_null("Settings")
	_race_setup = root.get_node_or_null("RaceSetup")
	_track_selection = root.get_node_or_null("TrackSelection")
	_championship = root.get_node_or_null("Championship")
	if _settings == null or _race_setup == null or _track_selection == null or _championship == null:
		push_error("validate_race_end_flow: autoloads missing")
		quit(1)
		return

	# main.gd reads the selected track in its own _ready(), so this has to be
	# pinned before the scene is instantiated.
	_race_setup.race_class = _race_setup.RACE_CLASS_VENOM
	_race_setup.pilot_name = "John Dekka"
	var scene: String = _track_selection.scene_for_circuit(CIRCUIT, _race_setup.RACE_CLASS_VENOM)
	if scene == "":
		push_error("validate_race_end_flow: no venom track for %s" % CIRCUIT)
		quit(1)
		return
	_track_selection.select_track(scene)

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("validate_race_end_flow: failed to load main.tscn")
		quit(1)
		return
	_main = packed.instantiate() as Node3D
	root.add_child(_main)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# RaceDirector.start_race() is deferred out of its _ready(), so the grid and
	# the player reference are not there on the first tick.
	if _frames < 6:
		return false

	_director = _main.get_node_or_null("RaceDirector")
	var hud := _main.find_child("RaceHud", true, false)
	_results = hud.get_node_or_null("Results") as Control if hud != null else null
	if _director == null or _results == null or _director.player == null:
		push_error("validate_race_end_flow: race scene did not come up (director=%s results=%s)" % [_director, _results])
		quit(1)
		return true

	_orig_lap_records = _settings.lap_records.duplicate(true)
	_orig_race_records = _settings.race_records.duplicate(true)
	_orig_has_rapier_class = _settings.has_rapier_class
	_orig_has_bonus_circuits = _settings.has_bonus_circuits

	_check_single_race_with_record()
	_check_single_race_without_record()
	_check_championship_with_record()
	_check_championship_without_qualifying()
	_check_championship_completed()
	_check_pause_game_over_releases_control()

	_settings.lap_records = _orig_lap_records
	_settings.race_records = _orig_race_records
	_settings.has_rapier_class = _orig_has_rapier_class
	_settings.has_bonus_circuits = _orig_has_bonus_circuits
	_settings.save()

	if _failures.is_empty():
		print("validate_race_end_flow: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_race_end_flow: %s" % failure)
		quit(1)
	return true


## button_race_stats_continue()'s `g.is_new_race_record` branch: a single race
## fast enough to place detours through the hall of fame.
func _check_single_race_with_record() -> void:
	_race_setup.race_type = _race_setup.RACE_TYPE_SINGLE
	_finish([60.0, 60.0, 60.0], 1)

	_check("finishing shows the results screen", _results.visible)
	_check("the results open on RACE STATISTICS", _results._stage == _results.Stage.STATS)
	_check("the stats page dims the race behind it", _results.dims_background())
	_check("a placing time is flagged as a new race record", bool(_results._stats.get("is_new_race_record", false)))

	_press_continue()
	_check("a new record detours into the hall of fame", _results._stage == _results.Stage.HALL_OF_FAME)
	_check("the hall of fame loads the board it is about to splice into", _results._hof_entries.size() == _settings.NUM_HIGHSCORES)


## The same page with a time nobody would enter: straight to restart-or-quit.
func _check_single_race_without_record() -> void:
	_race_setup.race_type = _race_setup.RACE_TYPE_SINGLE
	var board: Array = _settings.get_race_records(CIRCUIT, _race_setup.RACE_CLASS_VENOM, false)
	var slower_than_last: float = float(board[-1]["time"]) + 60.0
	_finish([slower_than_last / 3.0, slower_than_last / 3.0, slower_than_last / 3.0], 1)

	_check("a time off the board is not a new race record", not bool(_results._stats.get("is_new_race_record", true)))
	_press_continue()
	_check("no record skips the hall of fame entirely", _results._stage == _results.Stage.RESTART_OR_QUIT)


## button_race_points_continue() / button_championship_points_continue(): a
## qualifying championship race walks the points pages first, and only then
## takes the same hall-of-fame detour.
func _check_championship_with_record() -> void:
	_race_setup.race_type = _race_setup.RACE_TYPE_CHAMPIONSHIP
	_championship.reset()
	_finish([60.0, 60.0, 60.0], 1)

	_check("championship stats open on RACE STATISTICS", _results._stage == _results.Stage.STATS)
	_check("finishing first qualifies", bool(_results._stats.get("qualified", false)))

	_press_continue()
	_check("qualifying goes to RACE POINTS", _results._stage == _results.Stage.RACE_POINTS)
	_press_continue()
	_check("race points go to the CHAMPIONSHIP TABLE", _results._stage == _results.Stage.CHAMPIONSHIP_TABLE)
	_press_continue()
	_check("a record still detours into the hall of fame before the next circuit", _results._stage == _results.Stage.HALL_OF_FAME)


## button_race_stats_continue()'s else-branch: finishing outside QUALIFYING_RANK
## never reaches the points pages at all, however fast the lap was -- it goes to
## the qualify-again confirm instead.
func _check_championship_without_qualifying() -> void:
	_race_setup.race_type = _race_setup.RACE_TYPE_CHAMPIONSHIP
	_championship.reset()
	# Last place, but on a record-setting time: the record must not smuggle the
	# run past the qualification gate.
	_finish([60.0, 60.0, 60.0], 8)

	_check("finishing last does not qualify", not bool(_results._stats.get("qualified", true)))
	_press_continue()
	_check("failing to qualify goes to the qualify-or-quit confirm", _results._stage == _results.Stage.QUALIFY_OR_QUIT)
	_check("failing to qualify never reaches RACE POINTS", _results._stage != _results.Stage.RACE_POINTS)
	_check("failing to qualify never reaches the hall of fame", _results._stage != _results.Stage.HALL_OF_FAME)


## race_next()'s "championship complete" branch: winning the last circuit ends
## on the congratulations crawl rather than loading another race, and that page
## is the one screen race_update() leaves undimmed (menu_is_scroll_text).
func _check_championship_completed() -> void:
	_race_setup.race_type = _race_setup.RACE_TYPE_CHAMPIONSHIP
	_settings.has_bonus_circuits = false
	_settings.has_rapier_class = false
	_championship.reset()
	# Park the campaign on its final non-bonus circuit.
	_championship.circuit_index = _championship.NUM_NON_BONUS_CIRCUITS - 1
	_check("the campaign is on its last circuit", _championship.is_championship_complete())

	# Qualify, but too slowly to place: no hall-of-fame detour in the way.
	var board: Array = _settings.get_race_records(CIRCUIT, _race_setup.RACE_CLASS_VENOM, false)
	var slow: float = (float(board[-1]["time"]) + 60.0) / 3.0
	_finish([slow, slow, slow], 1)

	_press_continue() # stats -> race points
	_press_continue() # race points -> championship table
	_press_continue() # championship table -> race_next()

	_check("completing the campaign reaches the congratulations crawl", _results._stage == _results.Stage.CONGRATULATIONS)
	_check("the crawl is loaded with the venom ending", _results._congratulations_lines == _championship.CONGRATULATIONS_VENOM)
	_check("finishing the venom campaign unlocks the rapier class", _settings.has_rapier_class)
	_check("the crawl is the one page that does not dim the race", not _results.dims_background())


## race_restart() calls race_release_control() before game_over_menu_init(), so
## running a championship out of lives from the pause menu has to clear
## SHIP_RACING too -- that flag is the only thing gating hud_draw(), so without
## it the GAME OVER screen keeps a live HUD (and a stale life count) on top of
## the frozen race.
func _check_pause_game_over_releases_control() -> void:
	var pause_menu := _main.find_child("PauseMenu", true, false)
	if pause_menu == null:
		_check("main.tscn has a PauseMenu", false)
		return

	_race_setup.race_type = _race_setup.RACE_TYPE_CHAMPIONSHIP
	_championship.reset()
	_championship.lives = 1 # last one, so RESTART ends the run without changing scene

	var player: Node = _director.player
	player.is_racing = true
	player.race_control_enabled = true

	pause_menu.pause()
	pause_menu.restart_race()

	_check("the pause game over releases race control", not player.race_control_enabled)
	_check("the pause game over stops the player racing, which hides the HUD", not player.is_racing)

	# The HUD has to keep processing while the tree is paused, or it never
	# notices and just freezes on its last pre-pause frame.
	var hud := _main.find_child("Hud", true, false)
	_check("the HUD keeps processing while paused", hud != null and hud.process_mode == Node.PROCESS_MODE_ALWAYS)

	paused = false


## Crosses the line on the last lap with the given per-lap times and rank, the
## way _on_lap_completed() does once ship.lap reaches NUM_LAPS.
func _finish(laps: Array, rank: int) -> void:
	var player: Node = _director.player
	player.lap_times.clear()
	for lap_time in laps:
		player.lap_times.append(float(lap_time))
	player.lap = NUM_LAPS
	player.position_rank = rank
	player.is_racing = true
	_director.state = STATE_RACING
	_director._end_race()


func _press_continue() -> void:
	for button in _results.get_node("Buttons").get_children():
		if button is Button and (button as Button).text == "CONTINUE":
			(button as Button).pressed.emit()
			return
	_failures.append("no CONTINUE button on stage %d" % _results._stage)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)
