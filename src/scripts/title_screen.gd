extends WipeoutMenu

## Title splash: src/wipeout/title.c, i.e. wiptitle.tim full screen with
## "PRESS ENTER" centred 40 units above the bottom edge in the DRFONTS font.
##
## title.c is not a menu page, but riding on WipeoutMenu keeps ui.c's anchor and
## scale maths in one place. The page carries no title and no entries, so
## nothing but the draw hook below is painted; the splash image is the scene's
## own TextureRect, kept behind this node's drawing with a negative z_index.
##
## The original also drops into an attract-mode race after ten idle seconds
## (title.c: has_shown_attract / duration > 5||10). This port mirrors that: ten
## seconds without an input starts RaceSetup.start_attract_mode(), which loads
## main.tscn straight into an all-AI demo race (see main.gd's
## _setup_attract_race()).

const MAIN_MENU := "res://scenes/MainMenu.tscn"

const PROMPT := "PRESS ENTER"

## title.c's ui_scaled_pos(UI_POS_BOTTOM | UI_POS_CENTER, vec2i(0, -40)).
const PROMPT_POS := Vector2(0.0, -40.0)

const IDLE_TIMEOUT := 10.0

var _idle_time: float = 0.0


func _wants_backdrop() -> bool:
	return false


func _build() -> void:
	push_page("", _draw_prompt)


func _process(delta: float) -> void:
	super._process(delta)
	_idle_time += delta
	if _idle_time >= IDLE_TIMEOUT:
		_idle_time = -INF # start_attract_mode() changes scene; never re-fire.
		RaceSetup.start_attract_mode(get_tree())


func _draw_prompt(_data: int, scale: float) -> void:
	WipeoutUI.draw_text_centered(
		self,
		PROMPT,
		_anchored(BOTTOM_CENTER, PROMPT_POS, scale),
		WipeoutUI.SIZE_8,
		WipeoutUI.COLOR_DEFAULT,
		scale
	)


## The page has no entries, so the shared handler ignores ui_accept.
func _unhandled_input(event: InputEvent) -> void:
	_idle_time = 0.0
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		GameAudio.play_select()
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	super._unhandled_input(event)


func _gui_input(event: InputEvent) -> void:
	_idle_time = 0.0
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		GameAudio.play_select()
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	super._gui_input(event)
