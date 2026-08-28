extends Control

## End-of-race statistics screen, ported from src/wipeout/ingame_menus.c's
## race_stats_menu_init() / page_race_stats_draw(): the CONGRATULATIONS or
## FAILED TO QUALIFY title, the pilot portrait, the race position, the three lap
## times, the total race time and the best lap -- at the same layout offsets,
## drawn with the DRFONTS bitmap font.
##
## The original chains on to RACE POINTS, championship points and the hall of
## fame; none of those are ported, so this ends on ingame_menus.c's
## button_restart_or_quit() choice instead.

const HUD_SCALE := 3.125 # same virtual-unit scale as race_hud.gd

const SIZE_8 := WipeoutUI.SIZE_8
const SIZE_16 := WipeoutUI.SIZE_16
const ACCENT := WipeoutUI.COLOR_ACCENT
const DEFAULT := WipeoutUI.COLOR_DEFAULT

## page_race_stats_draw(): title_pos is (0,-100) from MIDDLE|CENTER, and the
## body starts 140 left of and 32 below it.
const TITLE_OFFSET := Vector2(0, -100)
const BODY_OFFSET := Vector2(-140, -68)

@onready var buttons: VBoxContainer = $Buttons
@onready var restart_button: Button = $Buttons/RestartButton
@onready var quit_button: Button = $Buttons/QuitButton

var _stats: Dictionary = {}
var _portrait: Texture2D = null


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	var director := get_tree().get_first_node_in_group(&"race_director") as RaceDirector
	if director != null:
		director.race_finished.connect(_on_race_finished)


func _on_race_finished(stats: Dictionary) -> void:
	_stats = stats
	_portrait = _load_portrait(bool(stats.get("qualified", false)))
	visible = true
	# race_stats_menu_init() opens on SFX_MENU_SELECT.
	GameAudio.play_select()
	GameAudio.hook_menu(self)
	restart_button.grab_focus()
	queue_redraw()


func _draw() -> void:
	if _stats.is_empty():
		return

	# race.c dims the 3D view behind an in-race menu with a half-alpha black quad.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))

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

	# Not in page_race_stats_draw(): the original announces a new lap record on
	# the hall-of-fame page that follows, which is not ported.
	if bool(_stats.get("is_new_lap_record", false)):
		WipeoutUI.draw_text(self, "NEW LAP RECORD", _at(pos), SIZE_8, ACCENT, HUD_SCALE)


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


func _on_restart_pressed() -> void:
	TrackSelection.start_race(get_tree())


func _on_quit_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
