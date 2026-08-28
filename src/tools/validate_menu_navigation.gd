extends SceneTree

## Headless walk of the menu flow with real input events, checking that
## selecting an entry and backing out actually change scene.
##
## This is the only check that drives a menu through change_scene_to_file():
## a page that takes itself out of the tree mid-callback used to leave
## get_viewport() null behind it, which no structural check would catch. Watch
## the output for SCRIPT ERROR lines as well as the verdict below.

## action to fire -> scene expected once it settles.
const STEPS: Array[Array] = [
	["ui_accept", "RaceClassMenu"],  # START GAME
	["ui_accept", "RaceTypeMenu"],   # VENOM CLASS
	["ui_down", "RaceTypeMenu"],     # move to SINGLE RACE
	["ui_accept", "TeamMenu"],
	["ui_accept", "PilotMenu"],      # AG SYSTEMS
	["ui_accept", "CircuitMenu"],    # JOHN DEKKA, single race -> circuits
	["ui_cancel", "PilotMenu"],
	["ui_cancel", "TeamMenu"],
	["ui_cancel", "RaceTypeMenu"],
	["ui_cancel", "RaceClassMenu"],
	["ui_cancel", "MainMenu"],
	["ui_down", "MainMenu"],         # move to OPTIONS
	["ui_accept", "OptionsMenu"],
	["ui_accept", "OptionsControlsMenu"],
	["ui_cancel", "OptionsMenu"],
	["ui_cancel", "MainMenu"],
]

var _f := 0
var _step := -1
var _failures: Array[String] = []


func _initialize() -> void:
	change_scene_to_file("res://scenes/MainMenu.tscn")


func _process(_d: float) -> bool:
	_f += 1
	# Two frames per step: one to fire, one to let the scene change settle.
	if _f % 4 != 0:
		return false

	if _step >= 0 and _step < STEPS.size():
		var expected: String = STEPS[_step][1]
		var actual: String = str(current_scene.name) if current_scene != null else "<none>"
		if actual != expected:
			_failures.append("step %d (%s): reached %s, expected %s" % [
				_step, STEPS[_step][0], actual, expected
			])

	_step += 1
	if _step >= STEPS.size():
		if _failures.is_empty():
			print("validate_menu_navigation: OK")
			quit(0)
		else:
			for failure in _failures:
				push_error("validate_menu_navigation: %s" % failure)
			quit(1)
		return true

	_fire(str(STEPS[_step][0]))
	return false


func _fire(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
