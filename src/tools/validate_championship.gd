extends SceneTree

## Headless check of the campaign chain added to match src/wipeout/race.c's
## race_end() / race_next() and main_menu.c's button_pilot_select() /
## button_race_class_select(): Championship's scoring/lives/circuit-gate
## bookkeeping, PilotMenu.tscn starting a championship on the right circuit,
## and RaceClassMenu / CircuitMenu gating RAPIER CLASS / FIRESTAR on
## Settings' unlock flags.
##
## Autoload names are not compile-time identifiers in --script mode, so the
## live autoloads are fetched off the root instead of being preloaded.

var _failures: Array[String] = []
var _frames := 0

var _championship: Node = null
var _settings: Node = null
var _track_selection: Node = null
var _race_setup: Node = null
var _ship_selection: Node = null

## Restored at the end so running this validator never leaves the developer's
## real user://settings.cfg unlocked.
var _orig_has_rapier_class: bool = false
var _orig_has_bonus_circuits: bool = false


func _initialize() -> void:
	_championship = root.get_node_or_null("Championship")
	_settings = root.get_node_or_null("Settings")
	_track_selection = root.get_node_or_null("TrackSelection")
	_race_setup = root.get_node_or_null("RaceSetup")
	_ship_selection = root.get_node_or_null("ShipSelection")
	if _championship == null or _settings == null or _track_selection == null or _race_setup == null or _ship_selection == null:
		push_error("validate_championship: autoloads missing")
		quit(1)
		return


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	# Settings' own _ready() (which loads these flags from disk) is not
	# guaranteed to have run before _initialize() above, so the backup has to
	# be read here instead -- otherwise a real save with progress could get
	# permanently reset to locked by the restore below.
	_orig_has_rapier_class = _settings.has_rapier_class
	_orig_has_bonus_circuits = _settings.has_bonus_circuits

	_check_reset()
	_check_scoring()
	_check_circuit_gate()
	_check_complete_championship()
	_check_pilot_menu_start_circuit()
	_check_race_class_gate()
	_check_lives_spent_on_restart()
	_check_pause_menu_game_over()

	_settings.has_rapier_class = _orig_has_rapier_class
	_settings.has_bonus_circuits = _orig_has_bonus_circuits
	_settings.save()

	if _failures.is_empty():
		print("validate_championship: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_championship: %s" % failure)
		quit(1)
	return true


## game_reset_championship() + button_pilot_select()'s g.circuit = 0.
func _check_reset() -> void:
	_championship.reset()
	_check("lives start at NUM_LIVES", _championship.lives == _championship.NUM_LIVES)
	_check("circuit_index starts at 0", _championship.circuit_index == 0)
	_check("current_circuit is ALTIMA VII", _championship.current_circuit() == "ALTIMA VII")

	var ships: Array = _ship_selection.SHIPS
	_check("standings has one entry per pilot", _championship.standings.size() == ships.size())
	for ship in ships:
		var pilot := str(ship["pilot"])
		_check("%s starts at 0 points" % pilot, int(_championship.standings.get(pilot, -1)) == 0)


## race_end()'s championship block: def.race_points_for_rank by finish order,
## accumulated across races.
func _check_scoring() -> void:
	_championship.reset()
	var ships: Array = _ship_selection.SHIPS
	var order: Array[String] = []
	for ship in ships:
		order.append(str(ship["pilot"]))

	_championship.record_race_result(order)
	var first_race: Array = _championship.last_race_points_sorted()
	_check("race points sorted leader first", int(first_race[0]["points"]) >= int(first_race[-1]["points"]))
	_check("1st place gets 9 points", int(_championship.last_race_points.get(order[0], -1)) == 9)
	_check("2nd place gets 7 points", int(_championship.last_race_points.get(order[1], -1)) == 7)
	_check("last place gets 0 points", int(_championship.last_race_points.get(order[-1], -1)) == 0)
	_check("standings match this race after one round", int(_championship.standings.get(order[0], -1)) == 9)

	# A second race, same order: points accumulate rather than replace.
	_championship.record_race_result(order)
	_check("standings accumulate across races", int(_championship.standings.get(order[0], -1)) == 18)
	var table: Array = _championship.standings_sorted()
	_check("standings_sorted leader first", int(table[0]["points"]) >= int(table[-1]["points"]))


## race_next()'s completion gate: NUM_NON_BONUS_CIRCUITS (6) until bonus
## circuits are unlocked, NUM_WIPEOUT_CIRCUITS (7) after.
func _check_circuit_gate() -> void:
	_championship.reset()
	_settings.has_bonus_circuits = false

	_championship.circuit_index = 4 # about to finish circuit 5 of 6 (index 4 -> 5)
	_check("not complete before the 6th circuit", not _championship.is_championship_complete())
	_championship.circuit_index = 5 # about to finish circuit 6 of 6 (index 5 -> 6)
	_check("complete after the 6th circuit when bonus is locked", _championship.is_championship_complete())

	_settings.has_bonus_circuits = true
	_check("not complete after the 6th circuit once bonus is unlocked", not _championship.is_championship_complete())
	_championship.circuit_index = 6 # about to finish circuit 7 of 7 (index 6 -> 7)
	_check("complete after the 7th circuit once bonus is unlocked", _championship.is_championship_complete())

	_championship.circuit_index = 0
	_championship.advance_circuit()
	_check("advance_circuit steps circuit_index by one", _championship.circuit_index == 1)
	_check("advance_circuit moves to the next CIRCUIT_ORDER entry", _championship.current_circuit() == _track_selection.CIRCUIT_ORDER[1])


## race_next()'s unlock branches: VENOM always grants RAPIER CLASS; RAPIER
## grants the bonus circuit the first time, then plays the "_all_circuits"
## ending once both are already unlocked.
func _check_complete_championship() -> void:
	_settings.has_rapier_class = false
	_settings.has_bonus_circuits = false

	var venom_lines: Array = _championship.complete_championship(_race_setup.RACE_CLASS_VENOM)
	_check("finishing VENOM unlocks RAPIER CLASS", _settings.has_rapier_class)
	_check("finishing VENOM (bonus locked) plays the venom ending", venom_lines == _championship.CONGRATULATIONS_VENOM)

	var rapier_lines: Array = _championship.complete_championship(_race_setup.RACE_CLASS_RAPIER)
	_check("finishing RAPIER unlocks bonus circuits", _settings.has_bonus_circuits)
	_check("finishing RAPIER (bonus just unlocked) plays the rapier ending", rapier_lines == _championship.CONGRATULATIONS_RAPIER)

	var venom_all: Array = _championship.complete_championship(_race_setup.RACE_CLASS_VENOM)
	_check("finishing VENOM once bonus is unlocked plays the all-circuits ending", venom_all == _championship.CONGRATULATIONS_VENOM_ALL_CIRCUITS)

	var rapier_all: Array = _championship.complete_championship(_race_setup.RACE_CLASS_RAPIER)
	_check("finishing RAPIER once bonus is unlocked plays the all-circuits ending", rapier_all == _championship.CONGRATULATIONS_RAPIER_ALL_CIRCUITS)


## The bug this feature started from: button_pilot_select()'s g.circuit = 0 is
## CIRCUIT_ALTIMA_VII, not TrackSelection.TRACKS[0] (TERRAMAX).
func _check_pilot_menu_start_circuit() -> void:
	_championship.reset()
	var circuit: String = _championship.current_circuit()
	_check("championship starts on ALTIMA VII, not TRACKS[0]", circuit == "ALTIMA VII")

	var venom_scene: String = _track_selection.scene_for_circuit(circuit, _race_setup.RACE_CLASS_VENOM)
	var rapier_scene: String = _track_selection.scene_for_circuit(circuit, _race_setup.RACE_CLASS_RAPIER)
	_check("venom championship starts on Track02 (ALTIMA VII venom)", venom_scene == "res://scenes/Track02.tscn")
	_check("rapier championship starts on Track03 (ALTIMA VII rapier)", rapier_scene == "res://scenes/Track03.tscn")


## button_race_class_select(): a locked RAPIER CLASS is unselectable. Only the
## locked branch is exercised here -- the unlocked one calls
## get_tree().change_scene_to_file(), which is not something to trigger from
## this bare validator SceneTree. CircuitMenu's analogous FIRESTAR gate is
## exercised in depth by validate_circuit_menu.gd already.
func _check_race_class_gate() -> void:
	var packed := load("res://scenes/RaceClassMenu.tscn") as PackedScene
	if packed == null:
		_check("failed to load RaceClassMenu", false)
		return

	_settings.has_rapier_class = false
	var locked := packed.instantiate()
	root.add_child(locked)
	var before: int = _race_setup.race_class
	locked._select_class(_race_setup.RACE_CLASS_RAPIER)
	_check("RAPIER CLASS is not selectable while locked", _race_setup.race_class == before)
	locked.queue_free()


## race.c race_restart() spends a life on *every* championship restart, not just
## the qualify-again prompt: the pause menu's RESTART pays too, or the lives
## system can be skipped by pausing instead of retrying. Checked against
## Championship directly (driving PauseMenu itself would reload the race scene).
func _check_lives_spent_on_restart() -> void:
	_championship.reset()
	var start_lives: int = _championship.lives
	_check("a fresh championship starts on NUM_LIVES", start_lives == _championship.NUM_LIVES)

	var out_of_lives: bool = _championship.lose_life()
	_check("a restart costs one life", _championship.lives == start_lives - 1)
	_check("lives remain after the first restart", not out_of_lives)

	# Burn the rest: the last one has to report the run as over.
	for i in start_lives - 2:
		_check("still alive with %d lives left" % _championship.lives, not _championship.lose_life())
	_check("the last life ends the run", _championship.lose_life())
	_check("lives do not go negative into a fresh reset", _championship.lives <= 0)

	# game_reset_championship() puts them all back for the next campaign.
	_championship.reset()
	_check("reset restores the full complement of lives", _championship.lives == _championship.NUM_LIVES)


## The pause menu's own RESTART has to go through race_restart()'s life cost,
## and spending the last one has to land on GAME OVER instead of reloading the
## circuit. Driven through PauseMenu.restart_race() rather than show_game_over()
## so the wiring between the two is what is actually under test; the run is set
## up on its final life precisely because that branch returns before
## TrackSelection.start_race() would change scene out from under the validator.
func _check_pause_menu_game_over() -> void:
	var packed := load("res://scenes/PauseMenu.tscn") as PackedScene
	if packed == null:
		_check("failed to load PauseMenu", false)
		return
	var pause_menu := packed.instantiate()
	root.add_child(pause_menu)
	var page = pause_menu.get_node_or_null("Menu")
	if page == null or not page.has_method("show_game_over"):
		_check("PauseMenu's page exposes show_game_over()", false)
		pause_menu.queue_free()
		return

	_race_setup.race_type = _race_setup.RACE_TYPE_CHAMPIONSHIP
	_championship.reset()
	_championship.lives = 1 # on the last one, so RESTART ends the run here
	pause_menu.restart_race()

	_check("a pause-menu restart spends a championship life", _championship.lives == 0)
	var current = page.current_page()
	_check("spending the last life lands on GAME OVER", current != null and current.title == "GAME OVER")
	_check("game over clears the stack, so back cannot resume the race", page.page_depth() == 1)

	# The non-championship path is deliberately not driven here: it falls
	# straight through to start_race(), which would change the running scene out
	# from under the validator. The race_type guard in restart_race() is what
	# keeps it out, and _draw_lives()'s own guard is checked the same way.
	pause_menu.queue_free()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)
