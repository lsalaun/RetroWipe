extends SceneTree

## Headless check that every menu scene is a drawn WipeoutMenu page carrying the
## title, entry list and layout src/wipeout/main_menu.c gives it, and that none
## of them fall back to Godot's default widgets.

## scene -> expected page, straight from the matching page_*_init() in
## main_menu.c. `fixed_title` / `fixed_items` are its title_pos / items_pos;
## `centered` is MENU_ALIGN_CENTER, which flags_set() drops on the options pages.
const EXPECTED: Array[Dictionary] = [
	{
		"scene": "res://scenes/MainMenu.tscn",
		# page_main_init() really does pass "OPTIONS" as the main page's title.
		"title": "OPTIONS",
		"entries": ["START GAME", "OPTIONS", "QUIT"],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -110),
		"centered": true,
	},
	{
		"scene": "res://scenes/RaceClassMenu.tscn",
		"title": "SELECT RACING CLASS",
		"entries": ["VENOM CLASS", "RAPIER CLASS"],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -110),
		"centered": true,
	},
	{
		"scene": "res://scenes/RaceTypeMenu.tscn",
		"title": "SELECT RACE TYPE",
		"entries": ["CHAMPIONSHIP RACE", "SINGLE RACE", "TIME TRIAL"],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -110),
		"centered": true,
	},
	{
		"scene": "res://scenes/TeamMenu.tscn",
		"title": "SELECT YOUR TEAM",
		"entries": ["AG SYSTEMS", "AURICOM", "QIREX", "FEISAR"],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -110),
		"centered": true,
	},
	{
		"scene": "res://scenes/PilotMenu.tscn",
		"title": "CHOOSE YOUR PILOT",
		# RaceSetup starts with no team, so the page falls back to TEAM_ORDER[0].
		"entries": ["John Dekka", "Daniel Chang"],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -110),
		"centered": true,
	},
	{
		"scene": "res://scenes/CircuitMenu.tscn",
		"title": "SELECT RACING CIRCUIT",
		"entries": [
			"ALTIMA VII", "KARBONIS V", "TERRAMAX", "KORODERA",
			"ARRIDOS IV", "SILVERSTREAM", "FIRESTAR",
		],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -100),
		"centered": true,
	},
	{
		"scene": "res://scenes/OptionsMenu.tscn",
		"title": "OPTIONS",
		"entries": ["CONTROLS", "VIDEO", "AUDIO"],
		"fixed_title": Vector2(0, 30),
		"fixed_items": Vector2(0, -110),
		"centered": true,
	},
	{
		"scene": "res://scenes/OptionsVideoMenu.tscn",
		"title": "VIDEO OPTIONS",
		"entries": ["FULLSCREEN", "VERTICAL SYNC", "DRAW STATS"],
		"fixed_title": Vector2(-160, -100),
		"fixed_items": Vector2(-160, -60),
		"centered": false,
		"toggles": true,
	},
	{
		"scene": "res://scenes/OptionsAudioMenu.tscn",
		"title": "AUDIO OPTIONS",
		"entries": ["MASTER VOLUME"],
		"fixed_title": Vector2(-160, -100),
		"fixed_items": Vector2(-160, -80),
		"centered": false,
		"toggles": true,
	},
	{
		"scene": "res://scenes/OptionsControlsMenu.tscn",
		"title": "CONTROLS",
		"entries": [
			"THRUST", "REVERSE", "LEFT", "RIGHT", "UP", "DOWN",
			"BRAKE L", "BRAKE R", "RESET",
		],
		"fixed_title": Vector2(-160, -100),
		"fixed_items": Vector2(-160, -50),
		"centered": false,
	},
]

var _frames := 0
var _menus: Array[Control] = []
var _failures: Array[String] = []


func _initialize() -> void:
	for expected in EXPECTED:
		var packed := load(str(expected["scene"])) as PackedScene
		if packed == null:
			push_error("validate_menus: failed to load %s" % expected["scene"])
			quit(1)
			return
		var menu := packed.instantiate() as Control
		if menu == null:
			push_error("validate_menus: %s is not a Control" % expected["scene"])
			quit(1)
			return
		root.add_child(menu)
		_menus.append(menu)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	for i in EXPECTED.size():
		_check_menu(_menus[i], EXPECTED[i])

	if _failures.is_empty():
		print("validate_menus: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_menus: %s" % failure)
		quit(1)
	return true


func _check_menu(menu: Control, expected: Dictionary) -> void:
	var name := str(expected["scene"]).get_file()
	if not menu.has_method("current_page"):
		_failures.append("%s is not a WipeoutMenu" % name)
		return
	if _has_any_control_widget(menu):
		_failures.append("%s still builds itself from Godot widgets" % name)

	var page = menu.current_page()
	if page == null:
		_failures.append("%s pushed no page" % name)
		return

	_check("%s title" % name, page.title == expected["title"])
	_check("%s is MENU_FIXED" % name, page.layout_flags & menu.FIXED != 0)
	_check("%s title_pos" % name, page.title_pos == expected["fixed_title"])
	_check("%s items_pos" % name, page.items_pos == expected["fixed_items"])
	_check(
		"%s alignment" % name,
		(page.layout_flags & menu.ALIGN_CENTER != 0) == bool(expected["centered"])
	)

	var texts: Array[String] = []
	for entry in page.entries:
		texts.append(entry.text)
	_check("%s entries %s" % [name, texts], texts == Array(expected["entries"], TYPE_STRING, "", null))

	if expected.get("toggles", false):
		for entry in page.entries:
			_check("%s entry %s is a toggle" % [name, entry.text], not entry.options.is_empty())


## The drawn pages must not smuggle in a Button, Label or Slider.
func _has_any_control_widget(node: Node) -> bool:
	for child in node.get_children():
		if child is BaseButton or child is Label or child is Range:
			return true
		if _has_any_control_widget(child):
			return true
	return false


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)
