extends Node
class_name RaceDirector

## Race flow ported from src/wipeout/race.c plus the race-control half of
## ship.c: the 3-2-1-GO start countdown (ship_player_update_intro* /
## ship_ai_update_intro_await_go), the race clock, the player's lap times, and
## race_end()'s statistics and lap-record bookkeeping.
##
## Ranking stays in RaceField (ships.c's sort_rank_compare); this node only
## reads position_rank off the player. The intro fly-by camera, championship
## points table and hall-of-fame name entry are intentionally not ported.

const NUM_LAPS := 3 # game.h NUM_LAPS
const QUALIFYING_RANK := 3 # game.h QUALIFYING_RANK

## ship.h UPDATE_TIME_*: one countdown timer per ship, started at 200/30 s and
## counted down, with a voice sample as it passes each threshold.
const COUNTDOWN_START := 200.0 / 30.0
const COUNTDOWN_THREE := 150.0 / 30.0
const COUNTDOWN_TWO := 100.0 / 30.0
const COUNTDOWN_ONE := 50.0 / 30.0
const COUNTDOWN_GO := 0.0

## How long the HUD keeps flashing GO after the start. The original has no
## on-screen countdown at all (it is voice-only, over the intro fly-by camera);
## this port draws one because it has no intro camera to signal the start.
const GO_DISPLAY_TIME := 1.5

const BEATS: Array[Dictionary] = [
	{"at": COUNTDOWN_THREE, "label": "3", "sfx": "res://assets/sfx/voice_count_3.wav"},
	{"at": COUNTDOWN_TWO, "label": "2", "sfx": "res://assets/sfx/voice_count_2.wav"},
	{"at": COUNTDOWN_ONE, "label": "1", "sfx": "res://assets/sfx/voice_count_1.wav"},
	{"at": COUNTDOWN_GO, "label": "GO", "sfx": "res://assets/sfx/voice_count_go.wav"},
]

enum State {
	COUNTDOWN, ## ships gated, camera and physics live
	RACING,
	FINISHED, ## player crossed the line on lap NUM_LAPS; race_end() ran
}

signal countdown_beat(label: String)
signal race_started
signal player_lap_completed(lap_index: int, time: float)
## `stats` carries position / lap_times / race_time / best_lap / qualified /
## is_new_lap_record / lap_record, i.e. everything page_race_stats_draw() reads
## out of `g` and `save`.
signal race_finished(stats: Dictionary)

var state: int = State.COUNTDOWN
var countdown_timer: float = COUNTDOWN_START
var race_time: float = 0.0 # wall clock since GO; g.race_time is recomputed from the lap times at the finish, as in race_end()
var player: WipeoutShip = null
var stats: Dictionary = {}

var _next_beat := 0
var _voice: AudioStreamPlayer


func _ready() -> void:
	add_to_group(&"race_director")
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)
	# main.gd spawns the AI field in its own _ready(), which Godot runs *after*
	# this child's _ready(); defer so the whole grid is present.
	call_deferred("start_race")


## race.c race_start(): resets per-ship race control state and re-arms the
## countdown. Safe to call again to restart without reloading the scene.
func start_race() -> void:
	player = null
	stats = {}
	race_time = 0.0
	countdown_timer = COUNTDOWN_START
	_next_beat = 0
	state = State.COUNTDOWN

	for ship in _ships():
		ship.reset_race_state()
		ship.race_control_enabled = false
		if not ship.lap_completed.is_connected(_on_lap_completed):
			ship.lap_completed.connect(_on_lap_completed)
		if ship.is_player_controlled:
			player = ship


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_update_countdown(delta)
		State.RACING:
			race_time += delta


func _update_countdown(delta: float) -> void:
	countdown_timer -= delta
	while _next_beat < BEATS.size() and countdown_timer <= float(BEATS[_next_beat]["at"]):
		var beat: Dictionary = BEATS[_next_beat]
		_play_voice(str(beat["sfx"]))
		countdown_beat.emit(str(beat["label"]))
		_next_beat += 1
	if countdown_timer <= COUNTDOWN_GO:
		countdown_timer = 0.0
		_release_grid()


## The "GO" branch of ship_player_update_intro_await_go(): control is handed to
## the player, and the remotes start their staggered acceleration.
func _release_grid() -> void:
	state = State.RACING
	for ship in _ships():
		ship.race_control_enabled = true
	race_started.emit()


## Label the HUD should show, or "" when the countdown isn't on screen.
func countdown_label() -> String:
	if state == State.COUNTDOWN:
		if countdown_timer > COUNTDOWN_THREE:
			return ""
		if countdown_timer > COUNTDOWN_TWO:
			return "3"
		if countdown_timer > COUNTDOWN_ONE:
			return "2"
		return "1"
	if state == State.RACING and race_time < GO_DISPLAY_TIME:
		return "GO"
	return ""


func _on_lap_completed(ship: WipeoutShip, lap_index: int, time: float) -> void:
	# ship.c only ends the race on the player's own NUM_LAPS crossing; the
	# remotes keep circulating.
	if ship != player:
		return
	player_lap_completed.emit(lap_index, time)
	if ship.lap >= NUM_LAPS:
		_end_race()


## race.c race_end(): total time is the sum of the recorded laps (not the wall
## clock), best lap the smallest of them, then the lap record is submitted and
## the player loses control.
func _end_race() -> void:
	if state == State.FINISHED or player == null:
		return
	state = State.FINISHED

	var lap_times: Array[float] = []
	var total := 0.0
	var best := 0.0
	for i in NUM_LAPS:
		var lap := player.lap_times[i] if i < player.lap_times.size() else 0.0
		lap_times.append(lap)
		total += lap
		if i == 0 or lap < best:
			best = lap

	var record := Settings.get_lap_record(_circuit_name(), RaceSetup.race_class, _is_time_trial())
	var is_new_lap_record := Settings.submit_lap_record(_circuit_name(), RaceSetup.race_class, _is_time_trial(), best)
	# race_end()'s is_new_race_record: a *peek*, not an insert -- the actual
	# save.highscores insert only happens once the hall-of-fame name entry
	# completes (see race_results.gd), same as the C.
	var is_new_race_record := Settings.is_new_race_record(_circuit_name(), RaceSetup.race_class, _is_time_trial(), total)

	stats = {
		"position": player.position_rank,
		"lap_times": lap_times,
		"race_time": total,
		"best_lap": best,
		"qualified": player.position_rank <= QUALIFYING_RANK,
		"is_new_lap_record": is_new_lap_record,
		"is_new_race_record": is_new_race_record,
		"lap_record": record,
	}

	# race_release_control(): the ship stops being racing (which hides the HUD)
	# and coasts on instead of stopping dead.
	player.race_control_enabled = false
	player.is_racing = false

	# race_end()'s championship block: scores this race unconditionally --
	# even a failed qualification still hands out points -- before the player
	# is even told whether they personally qualified.
	if RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP:
		Championship.record_race_result(_finish_order())

	race_finished.emit(stats)


## The lap record the HUD shows for the current circuit / class / tab.
func current_lap_record() -> float:
	return Settings.get_lap_record(_circuit_name(), RaceSetup.race_class, _is_time_trial())


func _circuit_name() -> String:
	return RaceField.track_display_name()


## game.h highscore_tab: race and time trial keep separate records.
func _is_time_trial() -> bool:
	return RaceSetup.race_type == RaceSetup.RACE_TYPE_TIME_TRIAL


func _ships() -> Array[WipeoutShip]:
	var result: Array[WipeoutShip] = []
	for node in get_tree().get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship != null:
			result.append(ship)
	return result


## sort_rank_compare() + the position_rank writeback in ship.c's
## ships_update(): every pilot's name, ordered 1st..last by position_rank.
func _finish_order() -> Array[String]:
	var ships := _ships()
	ships.sort_custom(func(a: WipeoutShip, b: WipeoutShip): return a.position_rank < b.position_rank)
	var names: Array[String] = []
	for ship in ships:
		names.append(ship.pilot_name)
	return names


func _play_voice(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.play()
