extends WipeoutMenu

## Top-level menu: src/wipeout/main_menu.c's page_main_init
## (START GAME / OPTIONS / QUIT, with QUIT going through menu_confirm).
##
## The title really is "OPTIONS": page_main_init() passes that string to
## menu_push(), so the original draws it above START GAME too. It is kept here
## rather than corrected so the page matches the C build pixel for pixel.
##
## The original draws a spinning 3D model beside the highlighted entry
## (page_main_draw). Those menu models are not imported in this port, so the
## page shows the background only.

const RACE_CLASS_MENU := "res://scenes/RaceClassMenu.tscn"
const OPTIONS_MENU := "res://scenes/OptionsMenu.tscn"


func _build() -> void:
	# menu_pop() at page 0 does nothing, so the main menu has nowhere to go back
	# to; the title screen is only ever reached forwards.
	back_scene = ""

	var page := push_page("OPTIONS")
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	page.add_button(0, "START GAME", _start_game)
	page.add_button(1, "OPTIONS", _options)
	page.add_button(2, "QUIT", _quit)


func _start_game(_data: int) -> void:
	get_tree().change_scene_to_file(RACE_CLASS_MENU)


func _options(_data: int) -> void:
	get_tree().change_scene_to_file(OPTIONS_MENU)


func _quit(_data: int) -> void:
	push_confirm("ARE YOU SURE YOU", "WANT TO QUIT", "YES", "NO", _quit_confirm)


func _quit_confirm(data: int) -> void:
	if data:
		get_tree().quit()
	else:
		pop_page()
