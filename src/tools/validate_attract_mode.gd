extends SceneTree

## Headless checks for the attract/demo mode added to title_screen.gd / main.gd:
##  1. RaceSetup.start_attract_mode() picks a consistent class/track/pilot and
##     flips is_attract_mode without crashing (the scene-change call it makes
##     is a no-op harness artifact under `--script`, not a real transition).
##  2. main.gd's _setup_attract_race() path: the human ship placeholder is
##     gone, all NUM_PILOTS grid slots are AI, exactly one is the POV ship
##     (is_player_controlled + a live camera), the HUD is hidden, the demo
##     label is present, and the pause menu is disabled.
##  3. race_director.gd's guard: an attract-mode "player" lap >= NUM_LAPS must
##     NOT submit a lap record or flip the race to FINISHED, unlike a real one.
##
## Every autoload (RaceSetup/TrackSelection/Settings) is looked up dynamically
## through root.get_node(), never referenced by its bare global name: this
## script is compiled by `-s` before the engine registers autoload globals, so
## a static `RaceSetup.foo` reference fails to *compile* here even though the
## same line is fine in any ordinarily-loaded scene script. RaceDirector and
## RaceField are avoided the same way validate_race_logic.gd avoids them --
## both touch those same autoloads internally, and naming either as a static
## type would pull that compile-time failure in transitively.
##
## Usage: godot --headless -s res://tools/validate_attract_mode.gd

## RaceDirector.State
const STATE_COUNTDOWN := 0
const STATE_RACING := 1
const STATE_FINISHED := 2
## RaceDirector.NUM_LAPS / RaceField.NUM_PILOTS, copied rather than read off
## those classes for the reason in the header comment above.
const NUM_LAPS := 3
const NUM_PILOTS := 8

const MAIN_SCENE_FRAME := 2
const COUNTDOWN_FRAME_BUDGET := 700

var _frames := 0
var _main: Node3D = null
var _director: Node = null
var _race_setup: Node = null
var _track_selection: Node = null
var _settings: Node = null


func _initialize() -> void:
	_race_setup = root.get_node_or_null("RaceSetup")
	_track_selection = root.get_node_or_null("TrackSelection")
	_settings = root.get_node_or_null("Settings")
	if _race_setup == null or _track_selection == null or _settings == null:
		push_error("missing RaceSetup/TrackSelection/Settings autoload")
		quit(1)
		return
	if not _check_start_attract_mode():
		quit(1)


func _physics_process(_delta: float) -> bool:
	_frames += 1

	if _frames == MAIN_SCENE_FRAME:
		var scene := load("res://scenes/main.tscn") as PackedScene
		if scene == null:
			push_error("main.tscn failed to load")
			quit(1)
			return true
		_main = scene.instantiate() as Node3D
		root.add_child(_main)
		return false

	if _frames == MAIN_SCENE_FRAME + 2:
		if not _check_attract_grid():
			quit(1)
			return true
		return false

	if _frames <= MAIN_SCENE_FRAME + 2:
		return false

	if int(_director.state) == STATE_COUNTDOWN and _frames < COUNTDOWN_FRAME_BUDGET:
		return false

	if not _check_attract_race_never_finishes():
		quit(1)
		return true

	print("validate_attract_mode: OK")
	quit(0)
	return true


# -----------------------------------------------------------------------------
# 1. RaceSetup.start_attract_mode()


func _check_start_attract_mode() -> bool:
	_race_setup.start_attract_mode(self)

	if not _race_setup.is_attract_mode:
		push_error("start_attract_mode() did not set is_attract_mode")
		return false
	if int(_race_setup.race_type) != 1: # RaceSetup.RACE_TYPE_SINGLE
		push_error("start_attract_mode() should pick RACE_TYPE_SINGLE, got %s" % str(_race_setup.race_type))
		return false
	var race_class: int = _race_setup.race_class
	if race_class < 0 or race_class >= _race_setup.RACE_CLASSES.size():
		push_error("start_attract_mode() picked an out-of-range race_class %d" % race_class)
		return false
	if _race_setup.pilot_name == "":
		push_error("start_attract_mode() left pilot_name empty")
		return false
	var track_scene: PackedScene = _track_selection.selected_track_scene
	if track_scene == null:
		push_error("start_attract_mode() left no track selected")
		return false

	# Look the picked scene back up in TRACKS by path and compare its own
	# "RAPIER" suffix against the class that was rolled.
	var want_rapier: bool = race_class == int(_track_selection.RAPIER_CLASS)
	var path := track_scene.resource_path
	var matched := false
	for track in _track_selection.TRACKS:
		if track["scene"] == path:
			matched = true
			if str(track["name"]).ends_with(" RAPIER") != want_rapier:
				push_error("picked track %s does not match race_class %d" % [path, race_class])
				return false
	if not matched:
		push_error("picked track %s is not in TrackSelection.TRACKS" % path)
		return false

	print("start_attract_mode OK: class=", race_class, " pilot=", _race_setup.pilot_name, " track=", path)
	return true


# -----------------------------------------------------------------------------
# 2. main.gd's _setup_attract_race()


func _check_attract_grid() -> bool:
	_director = _main.get_node_or_null("RaceDirector")
	if _director == null:
		push_error("main.tscn has no RaceDirector")
		return false

	if _main.get_node_or_null("Ship") != null:
		push_error("the human ship placeholder should have been removed in attract mode")
		return false

	var hud := _main.get_node_or_null("RaceHud")
	if hud == null or hud.visible:
		push_error("RaceHud should be hidden in attract mode")
		return false

	if _main.get_node_or_null("DemoModeLayer") == null:
		push_error("expected a DemoModeLayer node")
		return false

	var pause_menu := _main.get_node_or_null("PauseMenu")
	if pause_menu == null or pause_menu.process_mode != Node.PROCESS_MODE_DISABLED:
		push_error("PauseMenu should be process-disabled in attract mode")
		return false

	var ships := get_nodes_in_group(&"ships")
	if ships.size() != NUM_PILOTS:
		push_error("expected %d ships, got %d" % [NUM_PILOTS, ships.size()])
		return false

	var reference_count := 0
	var ai_count := 0
	for node in ships:
		var ship := node as WipeoutShip
		if ship == null:
			push_error("non-WipeoutShip in the ships group")
			return false
		if not (ship is WipeoutShipAI):
			push_error("%s is not AI-driven in attract mode" % ship.name)
			return false
		ai_count += 1
		# No ship may hold the active camera: attract_camera.gd owns the view.
		var cam := ship.camera_rig.get_node_or_null("Camera3D") as Camera3D
		if cam != null and cam.current:
			push_error("%s still holds the active camera in attract mode" % ship.name)
			return false
		if ship.is_player_controlled:
			reference_count += 1
			if ship.use_cockpit_audio:
				push_error("DPA reference %s must not use the cockpit audio mix" % ship.name)
				return false

	if ai_count != NUM_PILOTS:
		push_error("expected all %d ships to be AI, got %d" % [NUM_PILOTS, ai_count])
		return false
	# race.c keeps exactly one g.pilot as the DPA / ranking reference.
	if reference_count != 1:
		push_error("expected exactly 1 DPA reference ship, got %d" % reference_count)
		return false

	if int(_director.state) != STATE_COUNTDOWN:
		push_error("expected the demo to open in COUNTDOWN, got %d" % int(_director.state))
		return false
	if _director.player == null:
		push_error("RaceDirector did not pick up the POV ship as player")
		return false

	print("attract grid OK: ships=", ships.size(), " reference=", (_director.player as WipeoutShip).name)
	return _check_attract_camera(ships)


## attract_camera.gd: the camera owns the view, cuts between treatments, tours
## the field, and always ends a frame aimed at its subject. Rolls are driven by
## hand rather than by waiting out VIEW_DURATION per cut, the way
## validate_race_logic.gd calls ship._update_race_progress() directly.
func _check_attract_camera(ships: Array) -> bool:
	var camera = _main.get_node_or_null("AttractCamera")
	if camera == null:
		push_error("expected an AttractCamera node in attract mode")
		return false
	if not camera.current:
		push_error("AttractCamera is not the active camera")
		return false
	if camera._subject == null:
		push_error("AttractCamera has no subject after setup()")
		return false

	var subjects_seen := {}
	var modes_seen := {}
	for i in 40:
		camera._roll_view()
		var subject: WipeoutShip = camera._subject
		if subject == null:
			push_error("roll %d left the camera without a subject" % i)
			return false
		if not ships.has(subject):
			push_error("roll %d picked a subject outside the field: %s" % [i, subject.name])
			return false
		subjects_seen[subject.name] = true
		modes_seen[int(camera._mode)] = true

		# Both treatments stand off the subject and aim at it.
		var to_subject: Vector3 = subject.global_position - camera.global_position
		if to_subject.length() < 0.5:
			push_error("roll %d put the camera inside its subject" % i)
			return false
		var aim: float = (-camera.global_transform.basis.z).dot(to_subject.normalized())
		if aim < 0.999:
			push_error("roll %d left the camera aimed off-subject (dot=%s)" % [i, str(aim)])
			return false

	# The roaming this whole change is about: 40 rolls over 8 ships must visit
	# more than one of them, and must exercise both camera treatments.
	if subjects_seen.size() < 2:
		push_error("camera never left its first subject over 40 rolls")
		return false
	if modes_seen.size() != 2:
		push_error("expected both ORBIT and STATIC treatments, saw %s" % str(modes_seen.keys()))
		return false

	# A STATIC view is a fixed vantage: the position must not drift between
	# frames, unlike ORBIT which walks its circle.
	if not _roll_until_mode(camera, 1): # AttractCamera.Mode.STATIC
		return false
	var parked: Vector3 = camera.global_position
	camera._process(0.1)
	if camera.global_position.distance_to(parked) > 0.001:
		push_error("a STATIC view must hold its vantage, moved %s" % str(camera.global_position.distance_to(parked)))
		return false

	if not _roll_until_mode(camera, 0): # AttractCamera.Mode.ORBIT
		return false
	var orbit_from: Vector3 = camera.global_position
	camera._process(1.0)
	if camera.global_position.distance_to(orbit_from) < 0.01:
		push_error("an ORBIT view must walk its circle, but the camera stood still")
		return false

	print("attract camera OK: subjects=", subjects_seen.size(), "/", ships.size(), " modes=", modes_seen.keys())
	return true


## Re-rolls until the camera lands on `mode`. The roll is a coin flip, so this
## is bounded rather than a `while`: a validator must not be able to hang.
func _roll_until_mode(camera, mode: int) -> bool:
	for i in 200:
		if int(camera._mode) == mode:
			return true
		camera._roll_view()
	push_error("camera never rolled into mode %d over 200 rolls" % mode)
	return false


# -----------------------------------------------------------------------------
# 3. race_director.gd's attract-mode guard


func _check_attract_race_never_finishes() -> bool:
	if int(_director.state) != STATE_RACING:
		push_error("countdown never released the grid (state=%d)" % int(_director.state))
		return false

	var player: WipeoutShip = _director.player
	var circuit_name := _circuit_name()
	var race_class: int = _race_setup.race_class
	var before_record: float = _settings.get_lap_record(circuit_name, race_class, false)
	player.lap = NUM_LAPS
	player.lap_times = [1.0, 1.0, 1.0]
	player.lap_completed.emit(player, NUM_LAPS - 1, 1.0)

	if int(_director.state) == STATE_FINISHED:
		push_error("attract mode must not let the demo race finish")
		return false
	var after_record: float = _settings.get_lap_record(circuit_name, race_class, false)
	if after_record != before_record:
		push_error("attract mode must not submit a lap record (%s -> %s)" % [str(before_record), str(after_record)])
		return false

	print("attract guard OK: state stayed ", int(_director.state), ", lap record unchanged at ", after_record)
	return true


## race_field.gd's track_display_name(), inlined for the same reason NUM_LAPS/
## NUM_PILOTS are copied above rather than read off RaceField.
func _circuit_name() -> String:
	var track_scene: PackedScene = _track_selection.selected_track_scene
	if track_scene == null:
		return "TERRAMAX"
	var path := track_scene.resource_path
	for track in _track_selection.TRACKS:
		if track["scene"] == path:
			return str(track.get("circuit", track["name"]))
	return "TERRAMAX"
