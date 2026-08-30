extends Control

## End-of-race flow, ported from src/wipeout/ingame_menus.c's
## race_stats_menu_init() / page_race_stats_draw(), button_race_stats_continue()'s
## qualify-or-quit confirm, page_race_points_draw(), page_championship_points_draw(),
## page_hall_of_fame_draw() (name entry for a new race-time record) and
## race.c's race_restart() (lives) / race_next() (circuit chaining, class and
## bonus-circuit unlocks, congratulations text).

const HUD_SCALE := 3.125 # same virtual-unit scale as race_hud.gd

const SIZE_8 := WipeoutUI.SIZE_8
const SIZE_16 := WipeoutUI.SIZE_16
const ACCENT := WipeoutUI.COLOR_ACCENT
const DEFAULT := WipeoutUI.COLOR_DEFAULT

## page_race_stats_draw(): title_pos is (0,-100) from MIDDLE|CENTER, and the
## body -- and page_race_points_draw()/page_championship_points_draw()'s
## tables -- start 140 left of and 32 below it.
const TITLE_OFFSET := Vector2(0, -100)
const BODY_OFFSET := Vector2(-140, -68)

## text_scroll_menu_draw(): the line list scrolls up the screen at a constant
## speed in the same virtual units HUD_SCALE turns into pixels.
const SCROLL_SPEED := 32.0

## page_hall_of_fame_draw()'s table: title_pos + (-120, 48), one row per
## Settings.NUM_HIGHSCORES entry, time column 120 units right of the name.
const HOF_BODY_OFFSET := Vector2(-120.0, -52.0)
const HOF_ROW_STEP := 24.0
const HOF_TIME_COLUMN := 120.0

## hs_charset "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", plus DEL (36) and END (37).
const HOF_CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const HOF_DEL_INDEX := 36
const HOF_END_INDEX := 37
## drfonts.cmp frames 7/8 (ui.c's UI_ICON_END/UI_ICON_DEL), already exported
## alongside the three DRFONTS font atlases.
const HOF_END_ICON := "res://assets/ui/drfonts/drfonts_07.png"
const HOF_DEL_ICON := "res://assets/ui/drfonts/drfonts_08.png"

enum Stage {
	STATS,
	RACE_POINTS,
	CHAMPIONSHIP_TABLE,
	QUALIFY_OR_QUIT,
	GAME_OVER,
	CONGRATULATIONS,
	HALL_OF_FAME,
	RESTART_OR_QUIT,
}

@onready var buttons: VBoxContainer = $Buttons

var _stage: int = Stage.STATS
var _stats: Dictionary = {}
var _portrait: Texture2D = null
var _congratulations_lines: Array[String] = []
var _congratulations_start_msec: int = 0

## Hall-of-fame name-entry state (hs_new_entry / hs_char_index in ingame_menus.c).
var _hof_name := ""
var _hof_char_index := 0
var _hof_time := 0.0
var _hof_entries: Array = []
var _hof_icon_cache: Dictionary = {}


func _ready() -> void:
	visible = false
	var director := get_tree().get_first_node_in_group(&"race_director") as RaceDirector
	if director != null:
		director.race_finished.connect(_on_race_finished)


func _process(_delta: float) -> void:
	if visible and _stage == Stage.CONGRATULATIONS:
		queue_redraw()


func _on_race_finished(stats: Dictionary) -> void:
	_stats = stats
	_portrait = _load_portrait(bool(stats.get("qualified", false)))
	visible = true
	# race_stats_menu_init() opens on SFX_MENU_SELECT.
	GameAudio.play_select()
	_show_stage(Stage.STATS)


func _is_championship() -> bool:
	return RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP


func _is_time_trial() -> bool:
	return RaceSetup.race_type == RaceSetup.RACE_TYPE_TIME_TRIAL


## menu_reset() + the page_*_init() for whichever screen comes next.
func _show_stage(stage: int) -> void:
	_stage = stage
	_clear_buttons()
	match stage:
		Stage.STATS:
			_add_button("CONTINUE", _on_stats_continue)
		Stage.RACE_POINTS:
			_add_button("CONTINUE", _on_race_points_continue)
		Stage.CHAMPIONSHIP_TABLE:
			_add_button("CONTINUE", _on_championship_table_continue)
		Stage.QUALIFY_OR_QUIT:
			_add_button("QUALIFY", _on_qualify_pressed)
			_add_button("QUIT", _on_quit_pressed)
		Stage.GAME_OVER:
			_add_button("CONTINUE", _on_quit_pressed)
		Stage.CONGRATULATIONS:
			_congratulations_start_msec = Time.get_ticks_msec()
			_add_button("CONTINUE", _on_quit_pressed)
		Stage.HALL_OF_FAME:
			# page_hall_of_fame_init() adds no menu_page_add_button(): input is
			# read directly (see _unhandled_input()), not through a button list.
			_hof_name = Settings.highscores_name
			_hof_char_index = 0
			_hof_time = float(_stats.get("race_time", 0.0))
			_hof_entries = Settings.get_race_records(RaceField.track_display_name(), RaceSetup.race_class, _is_time_trial())
		Stage.RESTART_OR_QUIT:
			_add_button("RESTART RACE", _on_restart_pressed)
			_add_button("QUIT TO MENU", _on_quit_pressed)
	GameAudio.hook_menu(self)
	queue_redraw()


func _clear_buttons() -> void:
	for child in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()


func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	buttons.add_child(button)
	if buttons.get_child_count() == 1:
		button.grab_focus()


# -----------------------------------------------------------------------------
# Stage transitions

## button_race_stats_continue(): championships branch on qualifying (RACE
## POINTS vs. the qualify-or-quit confirm); single race/time trial detour to
## HALL OF FAME on a new race-time record, same as the confirm-restart choice
## they would otherwise go straight to.
func _on_stats_continue() -> void:
	if _is_championship():
		if bool(_stats.get("qualified", false)):
			_show_stage(Stage.RACE_POINTS)
		else:
			_show_stage(Stage.QUALIFY_OR_QUIT)
	elif bool(_stats.get("is_new_race_record", false)):
		_show_stage(Stage.HALL_OF_FAME)
	else:
		_show_stage(Stage.RESTART_OR_QUIT)


## button_race_points_continue().
func _on_race_points_continue() -> void:
	_show_stage(Stage.CHAMPIONSHIP_TABLE)


## button_championship_points_continue(): a new race-time record still takes
## priority over continuing the campaign.
func _on_championship_table_continue() -> void:
	if bool(_stats.get("is_new_race_record", false)):
		_show_stage(Stage.HALL_OF_FAME)
	else:
		_continue_championship()


## race_next(), shared by button_championship_points_continue() and
## page_hall_of_fame_draw()'s hs_entry_complete branch (both call race_next()
## once there is no hall-of-fame detour left to take).
func _continue_championship() -> void:
	if Championship.is_championship_complete():
		_congratulations_lines = Championship.complete_championship(RaceSetup.race_class)
		_show_stage(Stage.CONGRATULATIONS)
	else:
		Championship.advance_circuit()
		_load_next_circuit()


## button_qualify_confirm(): QUALIFY costs a life (race_restart()); GAME OVER
## once none are left.
func _on_qualify_pressed() -> void:
	if Championship.lose_life():
		_show_stage(Stage.GAME_OVER)
	else:
		_on_restart_pressed()


# -----------------------------------------------------------------------------
# Hall of fame name entry

## hall_of_fame_draw_name_entry()'s per-frame bounds recompute: c_first/c_last,
## as the [lo, hi) range wrap_around() cycles hs_char_index through. An empty
## name excludes END (must type at least one character); a full one excludes
## every letter (only DEL/END remain reachable).
func _hof_bounds() -> Vector2i:
	var entry_len := _hof_name.length()
	if entry_len == 0:
		return Vector2i(0, HOF_END_INDEX)
	if entry_len >= 3:
		return Vector2i(HOF_DEL_INDEX, HOF_END_INDEX + 1)
	return Vector2i(0, HOF_END_INDEX + 1)


func _wrap(value: int, lo: int, hi: int) -> int:
	return lo + posmod(value - lo, hi - lo)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _stage != Stage.HALL_OF_FAME:
		return
	if event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_hof_char_index += 1
		queue_redraw()
	elif event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		_hof_char_index -= 1
		queue_redraw()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_hof_confirm()
		queue_redraw()


## A_MENU_SELECT / A_MENU_START on the current wheel position: DEL erases the
## last character, END finalises the entry, anything else appends the letter.
func _hof_confirm() -> void:
	var bounds := _hof_bounds()
	_hof_char_index = _wrap(_hof_char_index, bounds.x, bounds.y)
	if _hof_char_index == HOF_DEL_INDEX:
		GameAudio.play_select()
		if _hof_name.length() > 0:
			_hof_name = _hof_name.substr(0, _hof_name.length() - 1)
	elif _hof_char_index == HOF_END_INDEX:
		_hof_finish()
	else:
		GameAudio.play_select()
		_hof_name += HOF_CHARSET[_hof_char_index]


## page_hall_of_fame_draw()'s hs_entry_complete branch: persist the name and
## the record, then either continue the campaign or fall back to the ordinary
## restart/quit choice.
func _hof_finish() -> void:
	GameAudio.play_select()
	Settings.set_highscores_name(_hof_name)
	Settings.submit_race_record(RaceField.track_display_name(), RaceSetup.race_class, _is_time_trial(), _hof_name, _hof_time)
	if _is_championship():
		_continue_championship()
	else:
		_show_stage(Stage.RESTART_OR_QUIT)


func _load_next_circuit() -> void:
	var circuit := Championship.current_circuit()
	var scene := TrackSelection.scene_for_circuit(circuit, RaceSetup.race_class)
	if scene == "":
		push_warning("race_results: no track for %s in class %d" % [circuit, RaceSetup.race_class])
		_on_quit_pressed()
		return
	TrackSelection.select_track(scene)
	TrackSelection.start_race(get_tree())


func _on_restart_pressed() -> void:
	TrackSelection.start_race(get_tree())


func _on_quit_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# -----------------------------------------------------------------------------
# Drawing

func _draw() -> void:
	if _stats.is_empty():
		return

	# race.c dims the 3D view behind an in-race menu with a half-alpha black quad.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))

	match _stage:
		Stage.STATS:
			_draw_stats()
		Stage.RACE_POINTS:
			_draw_points_table("RACE POINTS", Championship.last_race_points_sorted())
		Stage.CHAMPIONSHIP_TABLE:
			_draw_points_table("CHAMPIONSHIP TABLE", Championship.standings_sorted())
		Stage.QUALIFY_OR_QUIT:
			WipeoutUI.draw_text_centered(self, "CONTINUE QUALIFYING OR QUIT", _at(TITLE_OFFSET), SIZE_8, ACCENT, HUD_SCALE)
		Stage.GAME_OVER:
			WipeoutUI.draw_text_centered(self, "GAME OVER", _at(TITLE_OFFSET), SIZE_16, ACCENT, HUD_SCALE)
		Stage.CONGRATULATIONS:
			_draw_congratulations()
		Stage.HALL_OF_FAME:
			_draw_hall_of_fame()
		Stage.RESTART_OR_QUIT:
			# menu_confirm(menu, "", "RESTART RACE", "RESTART", "QUIT", ...):
			# empty title, "RESTART RACE" as the (default-coloured) subtitle.
			WipeoutUI.draw_text_centered(self, "RESTART RACE", _at(TITLE_OFFSET), SIZE_8, DEFAULT, HUD_SCALE)


func _draw_stats() -> void:
	var is_time_trial: bool = RaceSetup.race_type == RaceSetup.RACE_TYPE_TIME_TRIAL
	if not is_time_trial:
		var title := "CONGRATULATIONS" if bool(_stats.get("qualified", false)) else "FAILED TO QUALIFY"
		WipeoutUI.draw_text_centered(self, title, _at(TITLE_OFFSET), SIZE_16, ACCENT, HUD_SCALE)

	var pos := BODY_OFFSET

	if not is_time_trial:
		_draw_portrait(Vector2(pos.x + 180, pos.y))
		WipeoutUI.draw_text(self, "RACE POSITION", _at(pos), SIZE_8, ACCENT, HUD_SCALE)
		var label_width := WipeoutUI.text_width("RACE POSITION", SIZE_8) + 8.0
		WipeoutUI.draw_text(
			self,
			str(_stats.get("position", 0)),
			_at(Vector2(pos.x + label_width, pos.y)),
			SIZE_8,
			DEFAULT,
			HUD_SCALE
		)

	pos.y += 32
	WipeoutUI.draw_text(self, "RACE STATISTICS", _at(pos), SIZE_8, ACCENT, HUD_SCALE)
	pos.y += 16

	var lap_times: Array = _stats.get("lap_times", [])
	for i in RaceDirector.NUM_LAPS:
		WipeoutUI.draw_text(self, "LAP", _at(Vector2(pos.x + 8, pos.y)), SIZE_8, ACCENT, HUD_SCALE)
		WipeoutUI.draw_text(self, str(i + 1), _at(Vector2(pos.x + 50, pos.y)), SIZE_8, ACCENT, HUD_SCALE)
		var lap: float = float(lap_times[i]) if i < lap_times.size() else 0.0
		WipeoutUI.draw_time(self, lap, _at(Vector2(pos.x + 72, pos.y)), SIZE_8, DEFAULT, HUD_SCALE)
		pos.y += 12

	pos.y += 32
	WipeoutUI.draw_text(self, "RACE TIME", _at(pos), SIZE_8, ACCENT, HUD_SCALE)
	pos.y += 12
	WipeoutUI.draw_time(self, float(_stats.get("race_time", 0.0)), _at(Vector2(pos.x + 8, pos.y)), SIZE_8, DEFAULT, HUD_SCALE)
	pos.y += 12

	WipeoutUI.draw_text(self, "BEST LAP", _at(pos), SIZE_8, ACCENT, HUD_SCALE)
	pos.y += 12
	WipeoutUI.draw_time(self, float(_stats.get("best_lap", 0.0)), _at(Vector2(pos.x + 8, pos.y)), SIZE_8, DEFAULT, HUD_SCALE)
	pos.y += 12

	# Not in page_race_stats_draw(): g.is_new_lap_record is set in race_end()
	# but the original UI never actually reads it anywhere (race.c sets it,
	# ingame_menus.c never checks it), so there is no original placement to
	# match here either. Kept as a small addition beyond the source game.
	if bool(_stats.get("is_new_lap_record", false)):
		WipeoutUI.draw_text(self, "NEW LAP RECORD", _at(pos), SIZE_8, ACCENT, HUD_SCALE)


## page_race_points_draw() / page_championship_points_draw(): "PILOT NAME" /
## "POINTS" columns, the current pilot's row in accent.
func _draw_points_table(title: String, rows: Array[Dictionary]) -> void:
	WipeoutUI.draw_text_centered(self, title, _at(TITLE_OFFSET), SIZE_16, ACCENT, HUD_SCALE)

	var pos := BODY_OFFSET
	WipeoutUI.draw_text(self, "PILOT NAME", _at(pos), SIZE_8, ACCENT, HUD_SCALE)
	WipeoutUI.draw_text(self, "POINTS", _at(Vector2(pos.x + 222, pos.y)), SIZE_8, ACCENT, HUD_SCALE)
	pos.y += 24

	for row in rows:
		var pilot := str(row.get("pilot", ""))
		var color := ACCENT if pilot == RaceSetup.pilot_name else DEFAULT
		WipeoutUI.draw_text(self, pilot.to_upper(), _at(pos), SIZE_8, color, HUD_SCALE)
		var points_text := str(int(row.get("points", 0)))
		var w := WipeoutUI.text_width(points_text, SIZE_8)
		WipeoutUI.draw_text(self, points_text, _at(Vector2(pos.x + 280 - w, pos.y)), SIZE_8, color, HUD_SCALE)
		pos.y += 12


## page_hall_of_fame_draw(): splices the still-being-typed entry into the
## sorted top-Settings.NUM_HIGHSCORES list at the row it would occupy once
## submitted, without touching the stored records until _hof_finish().
func _draw_hall_of_fame() -> void:
	WipeoutUI.draw_text_centered(self, "HALL OF FAME", _at(TITLE_OFFSET), SIZE_16, ACCENT, HUD_SCALE)

	var bounds := _hof_bounds()
	_hof_char_index = _wrap(_hof_char_index, bounds.x, bounds.y)

	var pos := HOF_BODY_OFFSET
	var entries_index := 0
	var inserted := false
	for _row in Settings.NUM_HIGHSCORES:
		if not inserted and entries_index < _hof_entries.size() and _hof_time < float(_hof_entries[entries_index]["time"]):
			_draw_hof_name_entry(pos)
			inserted = true
		else:
			var entry: Dictionary = _hof_entries[entries_index]
			WipeoutUI.draw_text(self, str(entry.get("name", "")), _at(pos), SIZE_16, DEFAULT, HUD_SCALE)
			WipeoutUI.draw_time(self, float(entry.get("time", 0.0)), _at(Vector2(pos.x + HOF_TIME_COLUMN, pos.y)), SIZE_16, DEFAULT, HUD_SCALE)
			entries_index += 1
		pos.y += HOF_ROW_STEP


## hall_of_fame_draw_name_entry(): the name typed so far, then either the
## DEL/END icon or the currently-selected letter, right after it -- a rotating
## cursor showing what A_MENU_SELECT would do next.
func _draw_hof_name_entry(pos: Vector2) -> void:
	WipeoutUI.draw_text(self, _hof_name, _at(pos), SIZE_16, ACCENT, HUD_SCALE)
	var cursor_pos := Vector2(pos.x + WipeoutUI.text_width(_hof_name, SIZE_16), pos.y)
	if _hof_char_index == HOF_DEL_INDEX:
		_draw_icon(HOF_DEL_ICON, cursor_pos)
	elif _hof_char_index == HOF_END_INDEX:
		_draw_icon(HOF_END_ICON, cursor_pos)
	else:
		WipeoutUI.draw_text(self, HOF_CHARSET[_hof_char_index], _at(cursor_pos), SIZE_16, ACCENT, HUD_SCALE)
	WipeoutUI.draw_time(self, _hof_time, _at(Vector2(pos.x + HOF_TIME_COLUMN, pos.y)), SIZE_16, DEFAULT, HUD_SCALE)


func _draw_icon(path: String, pos: Vector2) -> void:
	if not _hof_icon_cache.has(path):
		_hof_icon_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var texture: Texture2D = _hof_icon_cache[path]
	if texture == null:
		return
	var rect := Rect2(_at(pos), Vector2(texture.get_width(), texture.get_height()) * HUD_SCALE)
	draw_texture_rect(texture, rect, false, ACCENT)


## text_scroll_menu_draw(): the line list scrolls up from the bottom of the
## screen at a fixed speed; "#" lines are bigger/accent with extra spacing,
## like a movie credits crawl.
func _draw_congratulations() -> void:
	var elapsed := (Time.get_ticks_msec() - _congratulations_start_msec) / 1000.0
	var y := size.y - elapsed * HUD_SCALE * SCROLL_SPEED
	for line in _congratulations_lines:
		if line.begins_with("#"):
			y += 48.0 * HUD_SCALE
			WipeoutUI.draw_text_centered(self, line.substr(1), Vector2(size.x * 0.5, y), SIZE_16, ACCENT, HUD_SCALE)
			y += 32.0 * HUD_SCALE
		else:
			WipeoutUI.draw_text_centered(self, line, Vector2(size.x * 0.5, y), SIZE_8, DEFAULT, HUD_SCALE)
			y += 12.0 * HUD_SCALE


## page_race_stats_draw() puts a half-alpha black quad behind the portrait.
func _draw_portrait(offset: Vector2) -> void:
	if _portrait == null:
		return
	var rect := Rect2(_at(offset), Vector2(_portrait.get_width(), _portrait.get_height()) * HUD_SCALE)
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.5))
	draw_texture_rect(_portrait, rect, false, DEFAULT)


## def.pilots[g.pilot].portrait, entry 1 when the player qualified and 0 when
## they did not (ingame_menus.c). ShipSelection stores the _00 path.
func _load_portrait(qualified: bool) -> Texture2D:
	var path := ""
	for ship in ShipSelection.SHIPS:
		if str(ship.get("pilot", "")) == RaceSetup.pilot_name:
			path = str(ship.get("portrait", ""))
			break
	if path.is_empty():
		# Same fallback main.gd uses when the race was started without going
		# through the pilot menu.
		path = str(ShipSelection.SHIPS[0].get("portrait", ""))
	if path.is_empty():
		return null
	if qualified:
		path = path.replace("_00.png", "_01.png")
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _at(offset: Vector2) -> Vector2:
	return size * 0.5 + offset * HUD_SCALE
