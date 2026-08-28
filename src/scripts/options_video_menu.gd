extends WipeoutMenu

## Video options: src/wipeout/main_menu.c's page_options_video_init, i.e. a
## left-aligned block of toggles with the chosen option flush against the right
## edge of the 320-unit block.
##
## The original's list is tied to its own renderer (internal view roll, screen
## shake, UI scale, 240p/480p, CRT post effect). This port keeps the settings
## Settings actually persists; DRAW STATS is save.draw_stats reduced to its
## OFF / FPS values, which is what the HUD reads.

const OPTIONS_MENU := "res://scenes/OptionsMenu.tscn"

## main_menu.c's opts_off_on / opts_draw_stats.
const OPTS_OFF_ON: PackedStringArray = ["OFF", "ON"]
const OPTS_DRAW_STATS: PackedStringArray = ["OFF", "FPS"]


func _build() -> void:
	back_scene = OPTIONS_MENU

	var page := push_page("VIDEO OPTIONS")
	page.layout_flags = VERTICAL | FIXED
	page.title_pos = Vector2(-160.0, -100.0)
	page.title_anchor = MIDDLE_CENTER
	page.items_pos = Vector2(-160.0, -60.0)
	page.items_anchor = MIDDLE_CENTER
	page.block_width = 320

	page.add_toggle(1 if Settings.fullscreen else 0, "FULLSCREEN", OPTS_OFF_ON, _toggle_fullscreen)
	page.add_toggle(1 if Settings.vsync else 0, "VERTICAL SYNC", OPTS_OFF_ON, _toggle_vsync)
	page.add_toggle(1 if Settings.show_fps else 0, "DRAW STATS", OPTS_DRAW_STATS, _toggle_draw_stats)


func _toggle_fullscreen(data: int) -> void:
	Settings.set_fullscreen(data == 1)


func _toggle_vsync(data: int) -> void:
	Settings.set_vsync(data == 1)


func _toggle_draw_stats(data: int) -> void:
	Settings.set_show_fps(data == 1)
