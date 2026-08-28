extends SceneTree

## Headless check that CircuitMenu reproduces main_menu.c's page_circuit page:
## seven circuits in def.circuits order, each resolving to a venom and a rapier
## track scene, a preview image per circuit, and menu.c's fixed anchor maths.
##
## Autoload names are not compile-time identifiers in --script mode, so the live
## autoloads are fetched off the root instead of being preloaded.

const CIRCUIT_SCENE := "res://scenes/CircuitMenu.tscn"

var _menu: Control = null
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(CIRCUIT_SCENE) as PackedScene
	if packed == null:
		push_error("validate_circuit_menu: failed to load CircuitMenu")
		quit(1)
		return
	_menu = packed.instantiate() as Control
	if _menu == null:
		push_error("validate_circuit_menu: CircuitMenu is not a Control")
		quit(1)
		return
	root.add_child(_menu)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	var track_selection := root.get_node_or_null("TrackSelection")
	var race_setup := root.get_node_or_null("RaceSetup")
	if track_selection == null or race_setup == null:
		push_error("validate_circuit_menu: autoloads missing")
		quit(1)
		return true
	if not _menu.has_method("current_page"):
		push_error("validate_circuit_menu: CircuitMenu is not a WipeoutMenu")
		quit(1)
		return true

	var circuits: Array = track_selection.CIRCUIT_ORDER
	_check("seven circuits listed", circuits.size() == 7)
	_check("first circuit is ALTIMA VII", circuits[0] == "ALTIMA VII")

	var seen: Dictionary = {}
	var classes := [race_setup.RACE_CLASS_VENOM, race_setup.RACE_CLASS_RAPIER]
	for i in circuits.size():
		var circuit: String = circuits[i]
		for race_class in classes:
			var scene: String = track_selection.scene_for_circuit(circuit, race_class)
			_check("%s class %d has a track" % [circuit, race_class], scene != "")
			_check("%s class %d track exists" % [circuit, race_class], ResourceLoader.exists(scene))
			_check("%s class %d track is unique" % [circuit, race_class], not seen.has(scene))
			seen[scene] = true
		var image: String = track_selection.circuit_image_path(i)
		_check("%s has a preview" % circuit, ResourceLoader.exists(image))

	# All 14 TRACKS entries must be reachable through the seven circuits.
	_check("every track reachable", seen.size() == track_selection.TRACKS.size())

	# page_circuit_init()'s MENU_FIXED anchors, at the project's 1600x900 viewport.
	var page = _menu.current_page()
	_check("page title", page.title == "SELECT RACING CIRCUIT")
	_check("one entry per circuit", page.entries.size() == circuits.size())
	_check("page is MENU_FIXED", page.layout_flags & _menu.FIXED != 0)
	_check("title 30 units below the top edge", page.title_pos == Vector2(0, 30))
	_check("items 100 units above the bottom edge", page.items_pos == Vector2(0, -100))

	_menu.size = Vector2(1600, 900)
	_check("ui scale is 2 at 900p", _menu._ui_scale() == 2.0)
	_check(
		"title anchors to the top centre",
		_menu._anchored(page.title_anchor, page.title_pos, 2.0) == Vector2(800, 60)
	)
	_check(
		"items anchor to the bottom centre",
		_menu._anchored(page.items_anchor, page.items_pos, 2.0) == Vector2(800, 700)
	)
	# page_circuit_draw() centres a 128x74 image 25 units above the middle.
	_check(
		"preview top-left is centred 25 units above the middle",
		_menu._anchored(
			_menu.MIDDLE_CENTER, _menu.PREVIEW_POS - _menu.PREVIEW_SIZE * 0.5, 2.0
		) == Vector2(672, 326)
	)
	# The entry hit boxes must line up with the drawn list.
	_check("first entry hit at its own baseline", _menu.entry_at(Vector2(800, 706)) == 0)
	_check("nothing hit above the list", _menu.entry_at(Vector2(800, 400)) == -1)

	if _failures.is_empty():
		print("validate_circuit_menu: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_circuit_menu: %s" % failure)
		quit(1)
	return true


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)
