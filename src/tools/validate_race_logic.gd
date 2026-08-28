extends SceneTree

## Headless checks for the in-race HUD + race logic:
##  1. WipeoutUI's DRFONTS atlases load and ui.c's metrics/time format match.
##  2. WipeoutShip's start-line lap counting (ship.c's start_line_pos crossing
##     test) on a synthetic closed curve, driven by calling
##     _update_race_progress() directly with physics disabled.
##  3. main.tscn wiring: RaceDirector gates the grid during the countdown, the
##     start-line offset is derived from TRACK.TRS's start_line_pos (not from
##     ShipSpawn, which sits 15 sections earlier), and the HUD resolves.
##
## RaceDirector is referenced dynamically on purpose: static typing would pull
## race_director.gd in while this script is compiled, before the autoloads it
## uses (Settings / RaceSetup) exist.
##
## Usage: godot --headless -s res://tools/validate_race_logic.gd

const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const CIRCLE_RADIUS := 200.0
const CIRCLE_POINTS := 48

## RaceDirector.State
const STATE_COUNTDOWN := 0
const STATE_RACING := 1

## Frame the main scene is instantiated on, and the frame budget for the
## countdown (RaceDirector.COUNTDOWN_START is 200/30 s, ~400 frames at 60 Hz).
const MAIN_SCENE_FRAME := 2
const COUNTDOWN_FRAME_BUDGET := 700

var _frames := 0
var _main: Node3D = null
var _director: Node = null


func _initialize() -> void:
	if not _check_font():
		quit(1)


func _physics_process(_delta: float) -> bool:
	_frames += 1

	# The synthetic ship must be inside the tree for global_transform / to_global
	# to work, so this cannot run from _initialize().
	if _frames == 1:
		if not _check_lap_counting():
			quit(1)
			return true
		return false

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
		if not _check_grid_gated():
			quit(1)
			return true
		return false

	if _frames <= MAIN_SCENE_FRAME + 2:
		return false

	if int(_director.state) == STATE_COUNTDOWN and _frames < COUNTDOWN_FRAME_BUDGET:
		return false
	if not _check_grid_released():
		quit(1)
		return true
	print("validate_race_logic: OK")
	quit(0)
	return true


# -----------------------------------------------------------------------------
# 1. Bitmap font


func _check_font() -> bool:
	for size in [WipeoutUI.SIZE_16, WipeoutUI.SIZE_12, WipeoutUI.SIZE_8]:
		var atlas: Texture2D = WipeoutUI.atlas(size)
		if atlas == null:
			push_error("WipeoutUI: no atlas for size index %d" % size)
			return false
		print("font size=", size, " atlas=", atlas.get_width(), "x", atlas.get_height())

	# ui.c char_set[UI_SIZE_8]: 'A' is 13 wide, '1' is 6, ':' is 4, ' ' is 8.
	var checks := [["A", 13.0], ["1", 6.0], [":", 4.0], [" ", 8.0]]
	for check in checks:
		var got: float = WipeoutUI.char_width(str(check[0]), WipeoutUI.SIZE_8)
		if not is_equal_approx(got, float(check[1])):
			push_error("char_width('%s') = %s, expected %s" % [check[0], str(got), str(check[1])])
			return false

	# "LAP" = 10 + 13 + 13 at size 8.
	var lap_width: float = WipeoutUI.text_width("LAP", WipeoutUI.SIZE_8)
	if not is_equal_approx(lap_width, 36.0):
		push_error("text_width('LAP') = %s, expected 36" % str(lap_width))
		return false

	# ui_draw_time()'s MM:SS.T layout.
	var time_checks := {0.0: "00:00.0", 85.83: "01:25.8", 3599.99: "59:59.9"}
	for value in time_checks:
		var got: String = WipeoutUI.format_time(float(value))
		if got != str(time_checks[value]):
			push_error("format_time(%s) = %s, expected %s" % [str(value), got, str(time_checks[value])])
			return false
	print("font metrics + time format OK")
	return true


# -----------------------------------------------------------------------------
# 2. Lap counting on a synthetic closed curve


func _check_lap_counting() -> bool:
	var path := Path3D.new()
	path.curve = _circle_curve()
	root.add_child(path)

	var ship_scene := load(SHIP_SCENE) as PackedScene
	if ship_scene == null:
		push_error("failed to load %s" % SHIP_SCENE)
		return false
	var ship := ship_scene.instantiate() as WipeoutShip
	ship.is_player_controlled = false
	root.add_child(ship)
	# Drive _update_race_progress() by hand: no hover rays, no rescue, no drift.
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ship.center_line = path

	var length := path.curve.get_baked_length()
	# Put the line a quarter of the way round, so offset 0 (where the curve
	# itself wraps) is nowhere near it -- that separation is what the old
	# wrap-at-offset-0 lap test could not express.
	ship.start_line_offset = length * 0.25
	ship.reset_race_state()

	var laps_seen: Array[int] = []
	var times_seen: Array[float] = []
	ship.lap_completed.connect(func(_s: WipeoutShip, lap_index: int, time: float) -> void:
		laps_seen.append(lap_index)
		times_seen.append(time)
	)

	# Start behind the line, like the grid does, and roll forward for 4 laps.
	var steps_per_lap := 60
	var step := length / float(steps_per_lap)
	var travelled := ship.start_line_offset - 40.0
	_place_on_curve(ship, path, travelled)
	ship._update_race_progress()
	if ship.lap != -1:
		push_error("expected lap -1 on the grid, got %d" % ship.lap)
		return false
	if ship.race_progress > 0.0:
		push_error("expected negative race_progress behind the line, got %s" % str(ship.race_progress))
		return false
	if not ship.direction_forward:
		push_error("expected direction_forward while facing down-track")
		return false

	var expected_laps := [0, 1, 2, 3]
	var lap_index := 0
	for i in steps_per_lap * 4 + 4:
		travelled += step
		ship.lap_time = 10.0 + float(lap_index) # distinct per-lap time to check banking
		_place_on_curve(ship, path, travelled)
		var before := ship.lap
		ship._update_race_progress()
		if ship.lap != before:
			if ship.lap != expected_laps[lap_index]:
				push_error("crossing %d gave lap %d, expected %d" % [lap_index, ship.lap, expected_laps[lap_index]])
				return false
			lap_index += 1
			if lap_index >= expected_laps.size():
				break

	if lap_index != 4:
		push_error("expected 4 forward crossings, got %d" % lap_index)
		return false
	# Crossing 0 only starts the first timed lap; laps 1..3 are banked.
	if str(laps_seen) != "[0, 1, 2]":
		push_error("expected lap_completed for indices [0,1,2], got %s" % str(laps_seen))
		return false
	if str(times_seen) != "[11.0, 12.0, 13.0]":
		push_error("expected banked times [11,12,13], got %s" % str(times_seen))
		return false
	if ship.lap_times.size() != 3:
		push_error("expected 3 lap times, got %d" % ship.lap_times.size())
		return false

	# Reverse back over the line: the lap comes off again, but max_lap keeps the
	# already-timed lap from being re-banked when it is crossed a second time.
	var backwards_from := travelled
	for i in 20:
		backwards_from -= step
		_place_on_curve(ship, path, backwards_from)
		ship._update_race_progress()
		if ship.lap == 2:
			break
	if ship.lap != 2:
		push_error("expected lap 2 after crossing backwards, got %d" % ship.lap)
		return false
	if not ship.direction_forward:
		push_error("direction_forward is orientation-based, so reversing along the curve must not clear it")
		return false
	for i in 24:
		backwards_from += step
		_place_on_curve(ship, path, backwards_from)
		ship._update_race_progress()
		if ship.lap == 3:
			break
	if ship.lap != 3:
		push_error("expected lap 3 after re-crossing forwards, got %d" % ship.lap)
		return false
	if laps_seen.size() != 3:
		push_error("re-crossing an already-timed lap must not bank a new time, got %s" % str(laps_seen))
		return false

	# Facing back up-track is what the HUD's WRONG WAY warning reads.
	_place_on_curve(ship, path, backwards_from, true)
	ship._update_race_progress()
	if ship.direction_forward:
		push_error("expected direction_forward == false while facing up-track")
		return false

	print("lap counting OK: laps=", laps_seen, " times=", times_seen)
	ship.remove_from_group(&"ships")
	ship.queue_free()
	path.queue_free()
	return true


func _circle_curve() -> Curve3D:
	var curve := Curve3D.new()
	for i in CIRCLE_POINTS:
		var angle := TAU * float(i) / float(CIRCLE_POINTS)
		curve.add_point(Vector3(cos(angle) * CIRCLE_RADIUS, 0.0, sin(angle) * CIRCLE_RADIUS))
	curve.closed = true
	return curve


func _place_on_curve(ship: WipeoutShip, path: Path3D, offset: float, backwards: bool = false) -> void:
	var curve := path.curve
	var length := curve.get_baked_length()
	var wrapped := fposmod(offset, length)
	var here := path.to_global(curve.sample_baked(wrapped, true))
	var ahead := path.to_global(curve.sample_baked(fposmod(wrapped + 2.0, length), true))
	var forward := ahead - here
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	if backwards:
		forward = -forward
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	ship.global_transform = Transform3D(Basis(right, up, -forward).orthonormalized(), here)


# -----------------------------------------------------------------------------
# 3. main.tscn wiring


func _check_grid_gated() -> bool:
	_director = _main.get_node_or_null("RaceDirector")
	if _director == null:
		push_error("main.tscn has no RaceDirector")
		return false
	if int(_director.state) != STATE_COUNTDOWN:
		push_error("expected the race to open in COUNTDOWN, got %d" % int(_director.state))
		return false
	if _director.player == null:
		push_error("RaceDirector did not find the player ship")
		return false

	var hud := _main.get_node_or_null("RaceHud/Hud")
	var results := _main.get_node_or_null("RaceHud/Results")
	if hud == null or results == null:
		push_error("RaceHud is missing Hud/Results")
		return false
	if results.visible:
		push_error("the results panel must start hidden")
		return false

	var ships := get_nodes_in_group(&"ships")
	if ships.is_empty():
		push_error("no ships in the race")
		return false
	for node in ships:
		var ship := node as WipeoutShip
		if ship == null:
			continue
		if ship.race_control_enabled:
			push_error("%s is not gated during the countdown" % ship.name)
			return false
		if ship.lap != -1:
			push_error("%s should start on lap -1, got %d" % [ship.name, ship.lap])
			return false
		if ship.start_line_offset <= 0.0:
			push_error("%s has no start_line_offset" % ship.name)
			return false
		if ship.race_progress > 0.0:
			push_error("%s starts in front of the line: progress=%s" % [ship.name, str(ship.race_progress)])
			return false

	var player: WipeoutShip = _director.player
	print(
		"grid gated: ships=", ships.size(),
		" start_line_offset=", snappedf(player.start_line_offset, 0.01),
		" player_progress=", snappedf(player.race_progress, 0.01),
		" lap_record=", WipeoutUI.format_time(_director.current_lap_record())
	)
	return true


func _check_grid_released() -> bool:
	if int(_director.state) != STATE_RACING:
		push_error("countdown never released the grid (state=%d)" % int(_director.state))
		return false
	for node in get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship != null and not ship.race_control_enabled:
			push_error("%s still gated after GO" % ship.name)
			return false
	print("grid released after ", _frames, " frames, race_time=", snappedf(_director.race_time, 0.01))
	return true
