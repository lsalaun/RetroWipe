extends WipeoutMenu

## BEST TIMES: src/wipeout/main_menu.c's page_options_highscores_init and the
## page_options_highscores_viewer_* it pushes on top.
##
## Two pages in one scene, matching the original's two menu_push()es onto the
## same menu_t: page 0 picks the tab (TIME TRIAL TIMES / RACE TIMES), page 1 is
## the table itself, and ui_cancel pops back exactly as menu_pop() does.
##
## The viewer has no menu entries -- the original reads its own navigation
## inside page_options_highscores_viewer_draw() via
## page_options_highscores_viewer_input_handler(). That is ported to
## _unhandled_input() instead, the same way the hall-of-fame name entry is,
## rather than polling input from a draw call.

const OPTIONS_MENU := "res://scenes/OptionsMenu.tscn"

## ALOPT.PRM's stopwatch, spun by page_options_highscores_draw().
const STOPWATCH_MODEL := "res://assets/menu_models/options/stopwatch/stopwatch.glb"
const PREVIEW_POS := Vector2(0.0, -40.0)
const PREVIEW_SIZE := Vector2(80.0, 80.0)

## game.h's highscore_tab enum, and the button data the original passes.
const TAB_TIME_TRIAL := 0
const TAB_RACE := 1

## page_options_highscores_viewer_draw()'s layout, all from MIDDLE|CENTER:
## class name at (0,-70), circuit 16 below it, then the five entries starting
## 24 lower and 110 left, their times back at x = 0, and the lap record last.
const CLASS_POS := Vector2(0.0, -70.0)
const CIRCUIT_POS := Vector2(0.0, -54.0)
const ENTRY_POS := Vector2(-110.0, -30.0)
const ENTRY_STEP := 24.0
const ENTRY_TIME_DX := 110.0
const LAP_LABEL_POS := Vector2(-150.0, 98.0)
const LAP_TIME_POS := Vector2(30.0, 94.0)

var _preview: MenuModelPreview
var _tab: int = TAB_TIME_TRIAL
var _class_index: int = 0
var _circuit_index: int = 0


func _build() -> void:
	back_scene = OPTIONS_MENU
	_preview = _add_model_preview()

	var page := push_page("VIEW BEST TIMES", _draw_stopwatch)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	# page_options_highscores_init() resets the viewer to Venom / Altima VII
	# every time the page is opened.
	_class_index = RaceSetup.RACE_CLASS_VENOM
	_circuit_index = 0

	page.add_button(TAB_TIME_TRIAL, "TIME TRIAL TIMES", _open_viewer)
	page.add_button(TAB_RACE, "RACE TIMES", _open_viewer)


func _draw_stopwatch(_data: int, scale: float) -> void:
	_preview.show_model(STOPWATCH_MODEL)
	_draw_model_preview(_preview, MIDDLE_CENTER, PREVIEW_POS, PREVIEW_SIZE, scale)


## button_highscores_viewer(): the button's data *is* the tab.
func _open_viewer(data: int) -> void:
	_tab = data
	var page := push_page("BEST TIME TRIAL TIMES" if data == TAB_TIME_TRIAL else "BEST RACE TIMES", _draw_table)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER


func _is_viewer_open() -> bool:
	return page_depth() > 1


func _circuits() -> Array[String]:
	return TrackSelection.CIRCUIT_ORDER


## page_options_highscores_viewer_input_handler(): up/down cycles the class,
## left/right the circuit, and any change blips SFX_MENU_MOVE.
##
## The original walks NUM_CIRCUITS (all 22 across the three games) and skips
## anything g.installed_circuits[] says is absent; this port ships only the
## seven WipEout circuits, so the list is CIRCUIT_ORDER and every entry is
## installed by construction.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_viewer_open():
		super._unhandled_input(event)
		return

	var last_class := _class_index
	var last_circuit := _circuit_index

	if event.is_action_pressed("ui_up"):
		_class_index -= 1
	elif event.is_action_pressed("ui_down"):
		_class_index += 1
	elif event.is_action_pressed("ui_left"):
		_circuit_index -= 1
	elif event.is_action_pressed("ui_right"):
		_circuit_index += 1
	else:
		# Nothing this page owns -- let the base class handle ui_cancel.
		super._unhandled_input(event)
		return

	_class_index = wrapi(_class_index, 0, RaceSetup.RACE_CLASSES.size())
	_circuit_index = wrapi(_circuit_index, 0, _circuits().size())
	get_viewport().set_input_as_handled()
	if last_class != _class_index or last_circuit != _circuit_index:
		GameAudio.play_move()
	queue_redraw()


## Which board the viewer is pointed at. Split out of _draw_table() so the
## class/circuit/tab selection can be asserted on directly -- the drawing
## itself has nothing a test can read back.
func current_circuit() -> String:
	return _circuits()[_circuit_index]


func current_entries() -> Array:
	return Settings.get_race_records(current_circuit(), _class_index, _tab == TAB_TIME_TRIAL)


func current_lap_record() -> float:
	return Settings.get_lap_record(current_circuit(), _class_index, _tab == TAB_TIME_TRIAL)


func _draw_table(_data: int, scale: float) -> void:
	var circuit := current_circuit()

	_text_centered(RaceSetup.RACE_CLASSES[_class_index], MIDDLE_CENTER, CLASS_POS, WipeoutUI.SIZE_12, WipeoutUI.COLOR_DEFAULT, scale)
	_text_centered(circuit, MIDDLE_CENTER, CIRCUIT_POS, WipeoutUI.SIZE_12, WipeoutUI.COLOR_ACCENT, scale)

	var entries := current_entries()
	var pos := ENTRY_POS
	for i in Settings.NUM_HIGHSCORES:
		if i >= entries.size():
			break
		var entry: Dictionary = entries[i]
		_text(str(entry.get("name", "")), MIDDLE_CENTER, pos, WipeoutUI.SIZE_16, WipeoutUI.COLOR_DEFAULT, scale)
		_time(float(entry.get("time", 0.0)), MIDDLE_CENTER, Vector2(pos.x + ENTRY_TIME_DX, pos.y), scale)
		pos.y += ENTRY_STEP

	_text("LAP RECORD", MIDDLE_CENTER, LAP_LABEL_POS, WipeoutUI.SIZE_12, WipeoutUI.COLOR_ACCENT, scale)
	_time(current_lap_record(), MIDDLE_CENTER, LAP_TIME_POS, scale)


func _time(seconds: float, anchor: Vector2, offset: Vector2, scale: float) -> void:
	WipeoutUI.draw_time(self, seconds, _anchored(anchor, offset, scale), WipeoutUI.SIZE_16, WipeoutUI.COLOR_DEFAULT, scale)
