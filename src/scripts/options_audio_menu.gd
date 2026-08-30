extends WipeoutMenu

## Audio options: src/wipeout/main_menu.c's page_options_audio_init, laid out
## like the video page and stepping each volume in tens through opts_volume.
## Music and sound effects are independent entries/buses, matching
## toggle_music_volume()/toggle_sfx_volume() exactly.

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

	var music_steps := clampi(roundi(Settings.music_volume * 10.0), 0, OPTS_VOLUME.size() - 1)
	page.add_toggle(music_steps, "MUSIC VOLUME", OPTS_VOLUME, _toggle_music_volume)

	var sfx_steps := clampi(roundi(Settings.sfx_volume * 10.0), 0, OPTS_VOLUME.size() - 1)
	page.add_toggle(sfx_steps, "SOUND EFFECTS VOLUME", OPTS_VOLUME, _toggle_sfx_volume)


func _toggle_music_volume(data: int) -> void:
	Settings.set_music_volume(float(data) * 0.1)


func _toggle_sfx_volume(data: int) -> void:
	Settings.set_sfx_volume(float(data) * 0.1)
