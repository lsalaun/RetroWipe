extends WipeoutMenu

## Title splash: src/wipeout/title.c, i.e. wiptitle.tim full screen with
## "PRESS ENTER" centred 40 units above the bottom edge in the DRFONTS font.
##
## title.c is not a menu page, but riding on WipeoutMenu keeps ui.c's anchor and
## scale maths in one place. The page carries no title and no entries, so
## nothing but the draw hook below is painted; the splash image is the scene's
## own TextureRect, kept behind this node's drawing with a negative z_index.
##
## The original also drops into an attract-mode race after ten idle seconds.
## This port has no attract mode, so the splash simply waits.

const MAIN_MENU := "res://scenes/MainMenu.tscn"

const PROMPT := "PRESS ENTER"

## title.c's ui_scaled_pos(UI_POS_BOTTOM | UI_POS_CENTER, vec2i(0, -40)).
const PROMPT_POS := Vector2(0.0, -40.0)


func _wants_backdrop() -> bool:
	return false


func _build() -> void:
	push_page("", _draw_prompt)


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
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		GameAudio.play_select()
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	super._unhandled_input(event)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		GameAudio.play_select()
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	super._gui_input(event)
