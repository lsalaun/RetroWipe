extends WipeoutMenu

## Controls remapping: src/wipeout/main_menu.c's page_options_controls_init,
## page_options_control_draw and button_capture. The action names run down the
## left of the 320-unit block with the KEYBOARD and JOYSTICK columns
## right-aligned beside them; picking one pushes the AWAITING INPUT page, which
## binds the next key or pad button and gives up after three seconds.
##
## The original's trailing ANALOG RESPONSE toggle is left out: this port has no
## analog response curve to set.

const OPTIONS_MENU := "res://scenes/OptionsMenu.tscn"

## button_capture() gets three seconds before page_options_control_set_draw()
## pops the page.
const CAPTURE_SECONDS := 3.0

## What Settings reports for an action with no binding of that kind; the
## original simply draws nothing in that column.
const UNBOUND := "---"

## page_options_control_draw()'s two columns, as offsets from items_pos.x.
const KEYBOARD_COLUMN := 100
const HEADER_OFFSET := -20

## The C labels the PSX pad actions (UP / DOWN / LEFT / RIGHT / BRAKE L / ...).
## These are this port's equivalents, in Settings.REBINDABLE_ACTIONS order.
const ACTION_LABELS: Dictionary = {
	"ship_thrust": "THRUST",
	"ship_reverse": "REVERSE",
	"ship_steer_left": "LEFT",
	"ship_steer_right": "RIGHT",
	"ship_pitch_up": "UP",
	"ship_pitch_down": "DOWN",
	"ship_airbrake_left": "BRAKE L",
	"ship_airbrake_right": "BRAKE R",
	"ship_reset": "RESET",
}

var _capturing_action := ""
var _capture_deadline := 0.0


func _build() -> void:
	back_scene = OPTIONS_MENU

	var page := push_page("CONTROLS", _draw_bindings)
	# flags_set() rather than flags_add() in the C, so MENU_ALIGN_CENTER is
	# dropped and the whole page becomes left-aligned.
	page.layout_flags = VERTICAL | FIXED
	page.title_pos = Vector2(-160.0, -100.0)
	page.title_anchor = MIDDLE_CENTER
	page.items_pos = Vector2(-160.0, -50.0)
	page.items_anchor = MIDDLE_CENTER
	page.block_width = 320

	for i in Settings.REBINDABLE_ACTIONS.size():
		var action: String = Settings.REBINDABLE_ACTIONS[i]
		page.add_button(i, str(ACTION_LABELS.get(action, action.to_upper())), _select_action)


func _draw_bindings(_data: int, scale: float) -> void:
	var page := current_page()
	var keyboard_x := page.items_pos.x + page.block_width - KEYBOARD_COLUMN
	var joystick_x := page.items_pos.x + page.block_width
	var line_y := page.items_pos.y + HEADER_OFFSET

	_right_aligned("KEYBOARD", keyboard_x, line_y, WipeoutUI.COLOR_DEFAULT, scale)
	_right_aligned("JOYSTICK", joystick_x, line_y, WipeoutUI.COLOR_DEFAULT, scale)
	line_y += 20.0

	for i in Settings.REBINDABLE_ACTIONS.size():
		var action: String = Settings.REBINDABLE_ACTIONS[i]
		# The bindings of the highlighted row stay accent-coloured while the
		# action name beside them blinks.
		var color := WipeoutUI.COLOR_ACCENT if i == page.index else WipeoutUI.COLOR_DEFAULT

		var key_name := Settings.get_key_display_name(action)
		if key_name != UNBOUND:
			_right_aligned(key_name, keyboard_x, line_y, color, scale)

		var pad_name := Settings.get_pad_display_name(action)
		if pad_name != UNBOUND:
			_right_aligned(pad_name, joystick_x, line_y, color, scale)

		line_y += ITEM_STEP


func _right_aligned(text: String, right_x: float, y: float, color: Color, scale: float) -> void:
	var page := current_page()
	var pos := Vector2(right_x - WipeoutUI.text_width(text, WipeoutUI.SIZE_8), y)
	_text(text, page.items_anchor, pos, WipeoutUI.SIZE_8, color, scale)


# -----------------------------------------------------------------------------
# Capture

func _select_action(data: int) -> void:
	if data < 0 or data >= Settings.REBINDABLE_ACTIONS.size():
		return
	_capturing_action = Settings.REBINDABLE_ACTIONS[data]
	_capture_deadline = _now() + CAPTURE_SECONDS
	push_page("AWAITING INPUT", _draw_capture)


## page_options_control_set_draw()'s countdown. The original reads the pushed
## page's items_pos, which menu_push() never initialises; the auto-centred
## position this page would get is used instead so the digit lands just under
## the title.
func _draw_capture(_data: int, scale: float) -> void:
	var page := current_page()
	var remaining := _capture_deadline - _now()
	var digit := str(clampi(int(remaining + 1.0), 0, 3))
	var pos := _layout_items_pos(page) + Vector2(0.0, 24.0)
	WipeoutUI.draw_text_centered(
		self,
		digit,
		_anchored(page.items_anchor, pos, scale),
		WipeoutUI.SIZE_16,
		WipeoutUI.COLOR_DEFAULT,
		scale
	)


func _process(delta: float) -> void:
	super._process(delta)
	if _capturing_action != "" and _now() >= _capture_deadline:
		_end_capture()


func _unhandled_input(event: InputEvent) -> void:
	if _capturing_action == "":
		super._unhandled_input(event)
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
			Settings.rebind_key(_capturing_action, (event as InputEventKey).physical_keycode)
		_end_capture()
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		Settings.rebind_pad(_capturing_action, (event as InputEventJoypadButton).button_index)
		_end_capture()


## Ignore the mouse while a binding is being captured; clicking an entry
## underneath would start a second capture.
func _gui_input(event: InputEvent) -> void:
	if _capturing_action != "":
		return
	super._gui_input(event)


func _end_capture() -> void:
	_capturing_action = ""
	pop_page()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
