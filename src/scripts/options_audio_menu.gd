extends Control

## Audio options: src/wipeout/main_menu.c's page_options_audio_init
## (subset applicable to this port: master volume; the game has no
## separate music/sfx buses yet).

@onready var volume_slider: HSlider = $CenterContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $CenterContainer/VBoxContainer/VolumeRow/VolumeValueLabel
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	volume_slider.value = Settings.master_volume
	_refresh_volume_label()

	volume_slider.value_changed.connect(_on_volume_changed)
	back_button.pressed.connect(_on_back_pressed)
	GameAudio.hook_menu(self)
	volume_slider.grab_focus()


func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)
	_refresh_volume_label()


func _refresh_volume_label() -> void:
	volume_value_label.text = "%d%%" % roundi(Settings.master_volume * 100)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OptionsMenu.tscn")
