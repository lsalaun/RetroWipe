extends Control

## PSX track loading card (TEXTURES/nloadNN.tim) shown before main.tscn.
## Mapping is TRACKNN -> nloadNN, from TrackSelection.TRACKS.

const RACE_SCENE := "res://scenes/main.tscn"

@onready var art: TextureRect = $TextureRect
@onready var start_button: Button = $StartRaceButton

## Validators set this false so the screen never loads the race scene.
var advance_to_race: bool = true


func _ready() -> void:
	_apply_loading_art()
	start_button.pressed.connect(_on_start_pressed)
	if advance_to_race:
		start_button.grab_focus()
	else:
		start_button.disabled = true


func _apply_loading_art() -> void:
	var path := TrackSelection.selected_loading_path()
	if path == "" or not ResourceLoader.exists(path):
		push_warning("loading_screen: missing texture %s" % path)
		return
	art.texture = load(path) as Texture2D


func _on_start_pressed() -> void:
	if not advance_to_race:
		return
	get_tree().change_scene_to_file(RACE_SCENE)
