extends RefCounted

## Full-screen wipeout1.tim behind menu Controls (main_menu.c background).

const WIPEOUT1 := "res://assets/ui/wipeout1.png"


static func attach(root: Control) -> void:
	if root == null:
		return
	if root.get_node_or_null("WipeoutBackdrop") != null:
		return
	if not ResourceLoader.exists(WIPEOUT1):
		return
	var bg := TextureRect.new()
	bg.name = "WipeoutBackdrop"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 0.0
	bg.offset_top = 0.0
	bg.offset_right = 0.0
	bg.offset_bottom = 0.0
	bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bg.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.texture = load(WIPEOUT1) as Texture2D
	root.add_child(bg)
	root.move_child(bg, 0)
