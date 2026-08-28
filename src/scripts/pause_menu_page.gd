extends WipeoutMenu

## The drawn half of the in-race pause menu: src/wipeout/ingame_menus.c's
## pause_menu_init (CONTINUE / RESTART / QUIT / MUSIC) plus the RESTART and QUIT
## confirmations and the MUSIC track list. Opening and closing it, and pausing
## the tree, stay in the parent CanvasLayer (pause_menu.gd).
##
## The page keeps menu.c's default auto-centred layout: no MENU_FIXED, so the
## title and list are centred on the page's own height, drawn straight over the
## frozen race with no panel behind them, as the original does.


func _wants_backdrop() -> bool:
	return false


func _build() -> void:
	var page := push_page("PAUSED")
	page.add_button(0, "CONTINUE", _continue)
	page.add_button(0, "RESTART", _restart)
	page.add_button(0, "QUIT", _quit)
	page.add_button(0, "MUSIC", _music)


func _pause_menu() -> Node:
	return get_parent()


func _continue(_data: int) -> void:
	_pause_menu().resume()


func _restart(_data: int) -> void:
	push_confirm("ARE YOU SURE YOU", "WANT TO RESTART", "YES", "NO", _restart_confirm)


func _restart_confirm(data: int) -> void:
	if data:
		_pause_menu().restart_race()
	else:
		pop_page()


func _quit(_data: int) -> void:
	push_confirm("ARE YOU SURE YOU", "WANT TO QUIT", "YES", "NO", _quit_confirm)


func _quit_confirm(data: int) -> void:
	if data:
		_pause_menu().quit_to_main_menu()
	else:
		pop_page()


func _music(_data: int) -> void:
	var page := push_page("MUSIC")
	for i in GameAudio.MUSIC_NAMES.size():
		page.add_button(i, GameAudio.MUSIC_NAMES[i], _play_track)
	page.add_button(0, "RANDOM", _play_random)


## button_music_track(): picking a track loops it from then on.
func _play_track(data: int) -> void:
	GameAudio.play_music(data)
	GameAudio.music_mode = GameAudio.MusicMode.LOOP


func _play_random(_data: int) -> void:
	GameAudio.play_random_music()
