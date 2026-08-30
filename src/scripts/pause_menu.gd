extends CanvasLayer

## In-race pause menu: src/wipeout/ingame_menus.c's pause_menu_init. Opened with
## Escape / ui_cancel or pad Start; the page itself is drawn by the Menu child
## (pause_menu_page.gd), which is rebuilt on every open the way pause_menu_init
## re-pushes its page. No on-screen MENU button during the race.

const MAIN_MENU := "res://scenes/MainMenu.tscn"

@onready var menu: WipeoutMenu = $Menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.visible = false


func _input(event: InputEvent) -> void:
	# While a confirmation or the music list is open, back belongs to the menu
	# so it can pop that page, exactly as menu_pop() does.
	if menu.visible and menu.page_depth() > 1:
		return
	if event.is_action_pressed("ui_cancel") or _is_start_pressed(event):
		get_viewport().set_input_as_handled()
		if menu.visible:
			resume()
		else:
			pause()


func _is_start_pressed(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton) or not event.pressed or event.is_echo():
		return false
	return (event as InputEventJoypadButton).button_index == JOY_BUTTON_START


func is_open() -> bool:
	return menu.visible


func pause() -> void:
	menu.visible = true
	menu.reset_pages()
	get_tree().paused = true
	# pause_menu_init() opens on SFX_MENU_SELECT.
	GameAudio.play_select()


func resume() -> void:
	menu.visible = false
	get_tree().paused = false


## race.c race_restart(): the life is spent by the restart itself, not by the
## menu that asked for it, so a championship pays for a pause-menu RESTART just
## as it does for the qualify-again prompt -- and the last one ends the run on
## game_over_menu_init() instead of reloading the circuit.
func restart_race() -> void:
	if RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP and Championship.lose_life():
		menu.show_game_over()
		return
	get_tree().paused = false
	TrackSelection.start_race(get_tree())


func quit_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)
