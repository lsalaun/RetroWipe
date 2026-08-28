extends SceneTree

## Headless check that PauseMenu opens and closes the drawn ingame_menus.c page
## through pause()/resume(), pausing the tree with it, and that the race screen
## carries no on-track menu button.

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
		if _has_any_button(_menu):
			push_error("validate_pause_menu: the pause menu must be drawn, not built from Buttons")
			quit(1)
			return true
		_menu.call("pause")
		_phase = 1
		return false

	if _phase == 1:
		if not _check_open():
			quit(1)
			return true
		# ingame_menus.c's first entry is CONTINUE, which unpauses the race.
		var page = _page()
		var entries: Array = page.current_page().entries
		if entries.size() != 4 or entries[0].text != "CONTINUE":
			push_error("validate_pause_menu: expected CONTINUE / RESTART / QUIT / MUSIC")
			quit(1)
			return true
		page.activate_entry(entries[0])
		_phase = 2
		return false

	if not _check_closed():
		quit(1)
		return true
	print("validate_pause_menu: OK")
	quit(0)
	return true


func _page() -> Control:
	return _menu.get_node_or_null("Menu") as Control


func _check_closed() -> bool:
	var page := _page()
	if page == null:
		push_error("validate_pause_menu: missing Menu")
		return false
	if page.visible:
		push_error("validate_pause_menu: the menu should be hidden on track")
		return false
	if paused:
		push_error("validate_pause_menu: tree should not be paused")
		return false
	return true


func _check_open() -> bool:
	var page := _page()
	if page == null:
		push_error("validate_pause_menu: missing Menu")
		return false
	if not page.visible:
		push_error("validate_pause_menu: the menu should be visible")
		return false
	if not paused:
		push_error("validate_pause_menu: tree should be paused")
		return false
	return true


func _has_any_button(node: Node) -> bool:
	if node is BaseButton:
		return true
	for child in node.get_children():
		if _has_any_button(child):
			return true
	return false
