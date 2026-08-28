extends WipeoutMenu

## Circuit selection: src/wipeout/main_menu.c's page_circuit_init, with
## page_circuit_draw's 128x74 track.cmp preview of the highlighted circuit.
##
## The original lists the seven WIPEOUT circuits once and takes the venom or
## rapier variant of the track from g.race_class. TrackSelection.TRACKS holds
## one entry per variant, so scene_for_circuit() picks the pair member here.
##
## Only reached for SINGLE RACE / TIME TRIAL; championships always start on the
## first circuit (see pilot_menu.gd).

const PILOT_MENU := "res://scenes/PilotMenu.tscn"

## page_circuit_draw(): a 128x74 image centred 25 units above the screen middle.
const PREVIEW_POS := Vector2(0.0, -25.0)
const PREVIEW_SIZE := Vector2(128.0, 74.0)

var _previews: Array[Texture2D] = []


func _build() -> void:
	back_scene = PILOT_MENU

	var page := push_page("SELECT RACING CIRCUIT", _draw_preview)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -100.0)
	page.items_anchor = BOTTOM_CENTER

	for i in TrackSelection.CIRCUIT_ORDER.size():
		page.add_button(i, TrackSelection.CIRCUIT_ORDER[i], _select_circuit)
		var path := TrackSelection.circuit_image_path(i)
		if ResourceLoader.exists(path):
			_previews.append(load(path) as Texture2D)
		else:
			push_warning("circuit_menu: missing preview %s" % path)
			_previews.append(null)


func _draw_preview(data: int, scale: float) -> void:
	if data < 0 or data >= _previews.size():
		return
	var texture := _previews[data]
	if texture == null:
		return
	var top_left := _anchored(MIDDLE_CENTER, PREVIEW_POS - PREVIEW_SIZE * 0.5, scale)
	draw_texture_rect(texture, Rect2(top_left, PREVIEW_SIZE * scale), false)


func _select_circuit(data: int) -> void:
	var circuit: String = TrackSelection.CIRCUIT_ORDER[data]
	var scene := TrackSelection.scene_for_circuit(circuit, RaceSetup.race_class)
	if scene == "":
		push_warning("circuit_menu: no track for %s in class %d" % [circuit, RaceSetup.race_class])
		return
	TrackSelection.select_track(scene)
	TrackSelection.start_race(get_tree())
