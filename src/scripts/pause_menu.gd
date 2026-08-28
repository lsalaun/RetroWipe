extends CanvasLayer

## In-race pause menu: src/wipeout/ingame_menus.c's pause_menu_init
## (CONTINUE / RESTART / QUIT). Opened with Escape / ui_cancel or pad Start.
## No on-screen MENU button during the race.

@onready var panel: Panel = $Panel
@onready var menu_button: Button = $MenuButton
@onready var continue_button: Button = $Panel/CenterContainer/VBoxContainer/ContinueButton
@onready var restart_button: Button = $Panel/CenterContainer/VBoxContainer/RestartButton
@onready var quit_button: Button = $Panel/CenterContainer/VBoxContainer/QuitButton
@onready var quit_confirm: ConfirmationDialog = $QuitConfirmDialog
@onready var restart_confirm: ConfirmationDialog = $RestartConfirmDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_button.visible = false
	menu_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quit_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	restart_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_open(false)

	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_confirm.confirmed.connect(_on_quit_confirmed)
	restart_confirm.confirmed.connect(_on_restart_confirmed)


func _input(event: InputEvent) -> void:
	if quit_confirm.visible or restart_confirm.visible:
		return
	if event.is_action_pressed("ui_cancel") or _is_start_pressed(event):
		get_viewport().set_input_as_handled()
		if panel.visible:
			_resume()
		else:
			_pause()


func _is_start_pressed(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton) or not event.pressed or event.is_echo():
		return false
	return (event as InputEventJoypadButton).button_index == JOY_BUTTON_START


func _set_open(open: bool) -> void:
	panel.visible = open
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	menu_button.visible = false


func _pause() -> void:
	_set_open(true)
	get_tree().paused = true
	continue_button.grab_focus()


func _resume() -> void:
	_set_open(false)
	get_tree().paused = false


func _on_continue_pressed() -> void:
	_resume()


func _on_restart_pressed() -> void:
	restart_confirm.popup_centered()


func _on_restart_confirmed() -> void:
	get_tree().paused = false
	TrackSelection.start_race(get_tree())


func _on_quit_pressed() -> void:
	quit_confirm.popup_centered()


func _on_quit_confirmed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
