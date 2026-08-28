extends Control

## In-race HUD ported from src/wipeout/hud.c's hud_draw(): lap counter, race
## position, current and previous lap times, the circuit's lap record, the
## WRONG WAY warning and the optional FPS readout -- all drawn with the original
## DRFONTS bitmap font through WipeoutUI, at the layout coordinates hud.c uses.
##
## The speedo lives in the Speedo child (hud_speedo.gd). Weapon icon, target
## reticle and championship lives are not drawn: weapons and championship lives
## are not ported yet.
##
## hud.c positions everything in ui.c's virtual units and multiplies by the
## global ui_scale; HUD_SCALE plays that role here. 3.125 is the ratio the
## Speedo node already uses (a 400px wide facia for the 128px speedo.tim), so
## the text lines up with it at any window size.

const HUD_SCALE := 3.125

const SIZE_8 := WipeoutUI.SIZE_8
const SIZE_16 := WipeoutUI.SIZE_16
const ACCENT := WipeoutUI.COLOR_ACCENT
const DEFAULT := WipeoutUI.COLOR_DEFAULT

## Anchors from ui.c's ui_scaled_pos() flags, as fractions of the screen.
const TOP_LEFT := Vector2(0.0, 0.0)
const TOP_RIGHT := Vector2(1.0, 0.0)
const BOTTOM_LEFT := Vector2(0.0, 1.0)
const MIDDLE_CENTER := Vector2(0.5, 0.5)

@onready var speedo: Control = $Speedo

var _ship: WipeoutShip = null
var _director: RaceDirector = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	_ship = _find_player()
	_director = _find_director()
	# race.c only calls hud_draw() while the ship still has SHIP_RACING, so the
	# whole HUD (speedo included) disappears once the player has finished.
	var racing := _ship != null and _ship.is_racing
	if speedo != null:
		speedo.visible = racing
	queue_redraw()


func _draw() -> void:
	if _ship == null or not _ship.is_racing:
		return

	_draw_lap_times()
	_draw_lap_counter()
	_draw_position()
	_draw_lap_record()
	_draw_stats()
	_draw_wrong_way()
	_draw_countdown()


## hud.c: current lap time bottom-left, with the already-banked laps stacked
## above it in the accent colour.
func _draw_lap_times() -> void:
	if _ship.lap < 0:
		return
	WipeoutUI.draw_time(self, _ship.lap_time, _at(Vector2(16, -30), BOTTOM_LEFT), SIZE_16, DEFAULT, HUD_SCALE)
	var shown := mini(_ship.lap_times.size(), RaceDirector.NUM_LAPS - 1)
	for i in shown:
		WipeoutUI.draw_time(
			self,
			_ship.lap_times[i],
			_at(Vector2(16, -45 - 10 * i), BOTTOM_LEFT),
			SIZE_8,
			ACCENT,
			HUD_SCALE
		)


## hud.c: "LAP <n> OF <NUM_LAPS>", where the "OF" sits just past the current
## lap's own digit so the layout stays tight for 1-digit numbers.
func _draw_lap_counter() -> void:
	var display_lap := maxi(0, _ship.lap + 1)
	WipeoutUI.draw_text(self, "LAP", _at(Vector2(15, 8)), SIZE_8, ACCENT, HUD_SCALE)
	WipeoutUI.draw_text(self, str(display_lap), _at(Vector2(10, 19)), SIZE_16, DEFAULT, HUD_SCALE)
	var width := WipeoutUI.char_width(str(display_lap).substr(0, 1), SIZE_16)
	WipeoutUI.draw_text(self, "OF", _at(Vector2(10 + width, 27)), SIZE_8, ACCENT, HUD_SCALE)
	WipeoutUI.draw_text(self, str(RaceDirector.NUM_LAPS), _at(Vector2(32 + width, 19)), SIZE_16, DEFAULT, HUD_SCALE)


## hud.c hides the rank in a time trial, where the player races alone.
func _draw_position() -> void:
	if RaceSetup.race_type == RaceSetup.RACE_TYPE_TIME_TRIAL:
		return
	WipeoutUI.draw_text(self, "POSITION", _at(Vector2(-90, 8), TOP_RIGHT), SIZE_8, ACCENT, HUD_SCALE)
	WipeoutUI.draw_text(self, str(_ship.position_rank), _at(Vector2(-60, 19), TOP_RIGHT), SIZE_16, DEFAULT, HUD_SCALE)


func _draw_lap_record() -> void:
	var record := _director.current_lap_record() if _director != null else Settings.NO_LAP_RECORD
	WipeoutUI.draw_text(self, "LAP RECORD", _at(Vector2(15, 43)), SIZE_8, ACCENT, HUD_SCALE)
	WipeoutUI.draw_time(self, record, _at(Vector2(15, 55)), SIZE_8, DEFAULT, HUD_SCALE)


## hud.c's DRAW_STATS_FPS branch (save.draw_stats). DRAW_STATS_DEBUG's triangle
## and draw-call counters have no direct equivalent here, so only the frame time
## is added next to the frame rate.
func _draw_stats() -> void:
	if not Settings.show_fps:
		return
	WipeoutUI.draw_text(self, "FPS", _at(Vector2(16, 78)), SIZE_8, ACCENT, HUD_SCALE)
	WipeoutUI.draw_text(self, str(Engine.get_frames_per_second()), _at(Vector2(16, 90)), SIZE_8, DEFAULT, HUD_SCALE)
	WipeoutUI.draw_text(self, "MS", _at(Vector2(64, 78)), SIZE_8, ACCENT, HUD_SCALE)
	var frame_ms := int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	WipeoutUI.draw_text(self, str(frame_ms), _at(Vector2(64, 90)), SIZE_8, DEFAULT, HUD_SCALE)


func _draw_wrong_way() -> void:
	if _ship.direction_forward:
		return
	WipeoutUI.draw_text_centered(self, "WRONG WAY", _at(Vector2(-20, 0), MIDDLE_CENTER), SIZE_16, ACCENT, HUD_SCALE)


## Not in hud.c: the original signals the start with voice samples over the
## intro fly-by camera, which this port does not have.
func _draw_countdown() -> void:
	if _director == null:
		return
	var label := _director.countdown_label()
	if label.is_empty():
		return
	WipeoutUI.draw_text_centered(self, label, _at(Vector2(0, -40), MIDDLE_CENTER), SIZE_16, DEFAULT, HUD_SCALE)


## ui.c ui_scaled_pos(): anchor fraction of the screen plus a scaled offset.
func _at(offset: Vector2, anchor: Vector2 = TOP_LEFT) -> Vector2:
	return size * anchor + offset * HUD_SCALE


func _find_player() -> WipeoutShip:
	if _ship != null and is_instance_valid(_ship):
		return _ship
	for node in get_tree().get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship != null and ship.is_player_controlled:
			return ship
	return null


func _find_director() -> RaceDirector:
	if _director != null and is_instance_valid(_director):
		return _director
	return get_tree().get_first_node_in_group(&"race_director") as RaceDirector
