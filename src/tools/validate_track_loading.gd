extends SceneTree

## Headless check that TRACKNN maps to nloadNN and LoadingScreen shows it.

const TrackSelectionScript = preload("res://scripts/track_selection.gd")
const LOADING_SCENE := "res://scenes/LoadingScreen.tscn"
const EXPECTED: Array[Dictionary] = [
	{"scene": "res://scenes/Track01.tscn", "loading": "res://assets/ui/nload01.png"},
	{"scene": "res://scenes/Track02.tscn", "loading": "res://assets/ui/nload02.png"},
	{"scene": "res://scenes/Track03.tscn", "loading": "res://assets/ui/nload03.png"},
	{"scene": "res://scenes/Track04.tscn", "loading": "res://assets/ui/nload04.png"},
	{"scene": "res://scenes/Track05.tscn", "loading": "res://assets/ui/nload05.png"},
	{"scene": "res://scenes/Track06.tscn", "loading": "res://assets/ui/nload06.png"},
	{"scene": "res://scenes/Track07.tscn", "loading": "res://assets/ui/nload07.png"},
	{"scene": "res://scenes/Track08.tscn", "loading": "res://assets/ui/nload08.png"},
	{"scene": "res://scenes/Track09.tscn", "loading": "res://assets/ui/nload09.png"},
	{"scene": "res://scenes/Track10.tscn", "loading": "res://assets/ui/nload10.png"},
	{"scene": "res://scenes/Track11.tscn", "loading": "res://assets/ui/nload11.png"},
	{"scene": "res://scenes/Track12.tscn", "loading": "res://assets/ui/nload12.png"},
	{"scene": "res://scenes/Track13.tscn", "loading": "res://assets/ui/nload13.png"},
	{"scene": "res://scenes/Track14.tscn", "loading": "res://assets/ui/nload14.png"},
]

var _frames := 0
var _screen: Control = null
var _ok := false


func _initialize() -> void:
	if not _check_catalog():
		quit(1)
		return
	if not _spawn_screen():
		quit(1)
		return


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if not _ok:
		quit(1)
		return true
	if not _check_shown_texture():
		quit(1)
		return true
	print("validate_track_loading: OK")
	quit(0)
	return true


func _selection() -> Node:
	return root.get_node_or_null("TrackSelection")


func _check_catalog() -> bool:
	if TrackSelectionScript.TRACKS.size() != EXPECTED.size():
		push_error("validate_track_loading: TRACKS size %d != %d" % [TrackSelectionScript.TRACKS.size(), EXPECTED.size()])
		return false
	var selection := _selection()
	if selection == null:
		push_error("validate_track_loading: TrackSelection autoload missing")
		return false
	for i in EXPECTED.size():
		var want: Dictionary = EXPECTED[i]
		var got: Dictionary = TrackSelectionScript.TRACKS[i]
		if str(got.get("scene", "")) != str(want["scene"]):
			push_error("validate_track_loading: scene[%d] %s != %s" % [i, got.get("scene", ""), want["scene"]])
			return false
		if str(got.get("loading", "")) != str(want["loading"]):
			push_error("validate_track_loading: loading[%d] %s != %s" % [i, got.get("loading", ""), want["loading"]])
			return false
		if not ResourceLoader.exists(str(want["loading"])):
			push_error("validate_track_loading: missing %s" % want["loading"])
			return false
		var mapped := str(selection.call("loading_path_for_scene", str(want["scene"])))
		if mapped != str(want["loading"]):
			push_error("validate_track_loading: map %s -> %s" % [want["scene"], mapped])
			return false
	return true


func _spawn_screen() -> bool:
	var selection := _selection()
	if selection == null:
		push_error("validate_track_loading: TrackSelection autoload missing")
		return false
	selection.call("select_track", "res://scenes/Track06.tscn")
	var packed := load(LOADING_SCENE) as PackedScene
	if packed == null:
		push_error("validate_track_loading: failed to load LoadingScreen")
		return false
	_screen = packed.instantiate() as Control
	if _screen == null:
		push_error("validate_track_loading: LoadingScreen is not Control")
		return false
	_screen.set("advance_to_race", false)
	root.add_child(_screen)
	_ok = true
	return true


func _check_shown_texture() -> bool:
	var art := _screen.get_node_or_null("TextureRect") as TextureRect
	if art == null or art.texture == null:
		push_error("validate_track_loading: TextureRect has no texture")
		return false
	var path := art.texture.resource_path
	if path != "res://assets/ui/nload06.png":
		push_error("validate_track_loading: shown %s, expected nload06.png" % path)
		return false
	var start_button := _screen.get_node_or_null("StartRaceButton") as Button
	if start_button == null:
		push_error("validate_track_loading: missing StartRaceButton")
		return false
	if start_button.text != "START RACE":
		push_error("validate_track_loading: StartRaceButton text %s" % start_button.text)
		return false
	if not start_button.disabled:
		push_error("validate_track_loading: StartRaceButton must stay disabled when advance_to_race is false")
		return false
	return true
