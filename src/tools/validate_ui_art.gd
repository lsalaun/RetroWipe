extends SceneTree

## Headless check for title, menu backdrop, portraits, and speedo HUD.

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")
const ShipSelectionScript := preload("res://scripts/ship_selection.gd")
const TITLE_SCENE := "res://scenes/TitleScreen.tscn"
const MAIN_MENU := "res://scenes/MainMenu.tscn"
const PILOT_MENU := "res://scenes/PilotMenu.tscn"
const HUD_SCENE := "res://scenes/RaceHud.tscn"
const WIPTITLE := "res://assets/ui/wiptitle.png"
const WIPEOUT1 := "res://assets/ui/wipeout1.png"
const SPEEDO := "res://assets/ui/speedo.png"

var _frames := 0
var _title: Control = null
var _menu: Control = null
var _pilot: Control = null
var _hud: CanvasLayer = null


func _initialize() -> void:
	if not _check_files():
		quit(1)
		return
	_title = _spawn(TITLE_SCENE) as Control
	_menu = _spawn(MAIN_MENU) as Control
	_pilot = _spawn(PILOT_MENU) as Control
	_hud = _spawn(HUD_SCENE) as CanvasLayer
	if _title == null or _menu == null or _pilot == null or _hud == null:
		push_error("validate_ui_art: failed to instantiate scenes")
		quit(1)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if not _check_title():
		quit(1)
		return true
	if not _check_menu():
		quit(1)
		return true
	if not _check_portraits():
		quit(1)
		return true
	if not _check_hud():
		quit(1)
		return true
	print("validate_ui_art: OK")
	quit(0)
	return true


func _spawn(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("validate_ui_art: missing %s" % path)
		return null
	var node := packed.instantiate()
	root.add_child(node)
	return node


func _check_files() -> bool:
	for path in [WIPTITLE, WIPEOUT1, SPEEDO]:
		if not ResourceLoader.exists(path):
			push_error("validate_ui_art: missing %s" % path)
			return false
	var ships: Array = ShipSelectionScript.SHIPS
	if ships.size() != 8:
		push_error("validate_ui_art: expected 8 ships")
		return false
	for ship in ships:
		var portrait := str(ship.get("portrait", ""))
		if portrait == "" or not ResourceLoader.exists(portrait):
			push_error("validate_ui_art: missing portrait %s" % portrait)
			return false
	return true


func _check_title() -> bool:
	var art := _title.get_node_or_null("TextureRect") as TextureRect
	if art == null or art.texture == null:
		push_error("validate_ui_art: title TextureRect empty")
		return false
	if art.texture.resource_path != WIPTITLE:
		push_error("validate_ui_art: title %s" % art.texture.resource_path)
		return false
	var start := _title.get_node_or_null("StartButton") as Button
	if start == null or start.text != "PRESS ENTER":
		push_error("validate_ui_art: title StartButton")
		return false
	return true


func _check_menu() -> bool:
	var bg := _menu.get_node_or_null("WipeoutBackdrop") as TextureRect
	if bg == null or bg.texture == null:
		push_error("validate_ui_art: MainMenu missing WipeoutBackdrop")
		return false
	if bg.texture.resource_path != WIPEOUT1:
		push_error("validate_ui_art: backdrop %s" % bg.texture.resource_path)
		return false
	if MenuBackdrop.WIPEOUT1 != WIPEOUT1:
		push_error("validate_ui_art: backdrop const mismatch")
		return false
	return true


func _check_portraits() -> bool:
	var portrait := _pilot.get_node_or_null("CenterContainer/HBoxContainer/Portrait") as TextureRect
	if portrait == null or portrait.texture == null:
		push_error("validate_ui_art: PilotMenu portrait empty")
		return false
	var path := str(portrait.texture.resource_path)
	if not path.begins_with("res://assets/ui/"):
		push_error("validate_ui_art: portrait path %s" % path)
		return false
	return true


func _check_hud() -> bool:
	# The speedo hangs off the text HUD so race_hud.gd can hide both together
	# when the ship loses SHIP_RACING (see race.c's hud_draw() gate).
	var facia := _hud.get_node_or_null("Hud/Speedo/Facia") as TextureRect
	if facia == null or facia.texture == null:
		push_error("validate_ui_art: speedo facia empty")
		return false
	if facia.texture.resource_path != SPEEDO:
		push_error("validate_ui_art: speedo %s" % facia.texture.resource_path)
		return false
	if _hud.get_node_or_null("Results") == null:
		push_error("validate_ui_art: RaceHud missing Results")
		return false
	for path in WipeoutUI.ATLAS_PATHS:
		if not ResourceLoader.exists(path):
			push_error("validate_ui_art: missing font atlas %s" % path)
			return false
	return true
