extends WipeoutMenu

## Audio options: src/wipeout/main_menu.c's page_options_audio_init, laid out
## like the video page and stepping the volume in tens through opts_volume.
##
## The original has one entry for music and one for sound effects. This port
## mixes everything through the Master bus (Settings.master_volume), so there is
## a single MASTER VOLUME entry until music and sfx get their own buses.

const OPTIONS_MENU := "res://scenes/OptionsMenu.tscn"

## main_menu.c's opts_volume.
const OPTS_VOLUME: PackedStringArray = [
	"0", "10", "20", "30", "40", "50", "60", "70", "80", "90", "100",
]


func _build() -> void:
	back_scene = OPTIONS_MENU

	var page := push_page("AUDIO OPTIONS")
	page.layout_flags = VERTICAL | FIXED
	page.title_pos = Vector2(-160.0, -100.0)
	page.title_anchor = MIDDLE_CENTER
	page.items_pos = Vector2(-160.0, -80.0)
	page.items_anchor = MIDDLE_CENTER
	page.block_width = 320

	var steps := clampi(roundi(Settings.master_volume * 10.0), 0, OPTS_VOLUME.size() - 1)
	page.add_toggle(steps, "MASTER VOLUME", OPTS_VOLUME, _toggle_volume)


func _toggle_volume(data: int) -> void:
	Settings.set_master_volume(float(data) * 0.1)
