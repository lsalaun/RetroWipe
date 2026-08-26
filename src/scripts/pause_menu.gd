extends CanvasLayer

## In-race pause menu: src/wipeout/ingame_menus.c's pause_menu_init
## (CONTINUE / RESTART / QUIT).

@onready var panel: Panel = $Panel
@onready var continue_button: Button = $Panel/CenterContainer/VBoxContainer/ContinueButton
@onready var restart_button: Button = $Panel/CenterContainer/VBoxContainer/RestartButton
@onready var quit_button: Button = $Panel/CenterContainer/VBoxContainer/QuitButton
@onready var quit_confirm: ConfirmationDialog = $QuitConfirmDialog
@onready var restart_confirm: ConfirmationDialog = $RestartConfirmDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false

	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_confirm.confirmed.connect(_on_quit_confirmed)
	restart_confirm.confirmed.connect(_on_restart_confirmed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if panel.visible:
			_resume()
		else:
			_pause()


func _pause() -> void:
	panel.visible = true
	get_tree().paused = true
	continue_button.grab_focus()


func _resume() -> void:
	panel.visible = false
	get_tree().paused = false


func _on_continue_pressed() -> void:
	_resume()


func _on_restart_pressed() -> void:
	restart_confirm.popup_centered()


func _on_restart_confirmed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	quit_confirm.popup_centered()


func _on_quit_confirmed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
