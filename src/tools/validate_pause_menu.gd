extends SceneTree

## Headless check that PauseMenu has no on-track MENU button and toggles via _pause/_resume.

const PAUSE_SCENE := "res://scenes/PauseMenu.tscn"

var _frames := 0
var _menu: CanvasLayer = null
var _phase := 0


func _initialize() -> void:
	var packed := load(PAUSE_SCENE) as PackedScene
	if packed == null:
		push_error("validate_pause_menu: failed to load PauseMenu")
		quit(1)
		return
	_menu = packed.instantiate() as CanvasLayer
	if _menu == null:
		push_error("validate_pause_menu: PauseMenu is not CanvasLayer")
		quit(1)
		return
	root.add_child(_menu)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _phase == 0:
		if not _check_closed():
			quit(1)
			return true
		if _menu.has_method("_pause"):
			_menu.call("_pause")
		else:
			push_error("validate_pause_menu: missing _pause")
			quit(1)
			return true
		_phase = 1
		return false
	if _phase == 1:
		if not _check_open():
			quit(1)
			return true
		var continue_button := _menu.get_node_or_null("Panel/CenterContainer/VBoxContainer/ContinueButton") as Button
		if continue_button == null:
			push_error("validate_pause_menu: missing ContinueButton")
			quit(1)
			return true
		continue_button.pressed.emit()
		_phase = 2
		return false
	if not _check_closed():
		quit(1)
		return true
	print("validate_pause_menu: OK")
	quit(0)
	return true


func _check_closed() -> bool:
	var panel := _menu.get_node_or_null("Panel") as Panel
	var menu_button := _menu.get_node_or_null("MenuButton") as Button
	if panel == null or menu_button == null:
		push_error("validate_pause_menu: missing Panel/MenuButton")
		return false
	if panel.visible:
		push_error("validate_pause_menu: panel should be hidden")
		return false
	if menu_button.visible:
		push_error("validate_pause_menu: MENU button must stay hidden on track")
		return false
	if paused:
		push_error("validate_pause_menu: tree should not be paused")
		return false
	return true


func _check_open() -> bool:
	var panel := _menu.get_node_or_null("Panel") as Panel
	var menu_button := _menu.get_node_or_null("MenuButton") as Button
	if panel == null or menu_button == null:
		push_error("validate_pause_menu: missing Panel/MenuButton")
		return false
	if not panel.visible:
		push_error("validate_pause_menu: panel should be visible")
		return false
	if menu_button.visible:
		push_error("validate_pause_menu: MENU button must stay hidden while paused")
		return false
	if not paused:
		push_error("validate_pause_menu: tree should be paused")
		return false
	return true
