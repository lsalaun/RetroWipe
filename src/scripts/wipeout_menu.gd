extends Control
class_name WipeoutMenu

## Port of src/wipeout/menu.c: the page stack, the layout flags and the drawing
## and input handling every page of the original menu shares, on top of
## WipeoutUI's DRFONTS bitmap font. Subclasses override _build() and declare
## their pages with push_page() / push_confirm() the way main_menu.c's
## page_*_init() functions do.
##
## The original keeps one menu_t for the whole main menu and pushes a page per
## screen. This port has one scene per top-level screen instead, so page 0 of a
## scene *is* that screen and `back_scene` stands in for popping past it;
## confirmations and other sub-pages are pushed on top as usual.

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

## menu.h's menu_page_layout_t.
const VERTICAL := 1 << 0
const HORIZONTAL := 1 << 1
const FIXED := 1 << 2
const ALIGN_CENTER := 1 << 3
const ALIGN_BLOCK := 1 << 4

## ui.h's UI_POS_* combinations, as fractions of the screen.
const TOP_CENTER := Vector2(0.5, 0.0)
const MIDDLE_CENTER := Vector2(0.5, 0.5)
const BOTTOM_CENTER := Vector2(0.5, 1.0)

## menu.c advances items_pos.y by 12 per entry.
const ITEM_STEP := 12.0

## Uniform multiplier applied to every menu's model/logo preview size in
## _draw_model_preview() below -- the single place to resize the spinning
## ship/icon previews across every menu screen at once.
const MODEL_PREVIEW_SCALE := 4.0


class Entry:
	const BUTTON := 0
	const TOGGLE := 1

	var type := BUTTON
	var data := 0
	var text := ""
	var options := PackedStringArray()
	var select := Callable()


class Page:
	var title := ""
	var subtitle := ""
	var layout_flags := 0
	var block_width := 320
	var title_pos := Vector2.ZERO
	var title_anchor := Vector2(0.5, 0.5)
	var items_pos := Vector2.ZERO
	var items_anchor := Vector2(0.5, 0.5)
	var index := 0
	var entries: Array = []

	## menu_page_t's draw_func, called as draw.call(selected_data, scale) once a
	## frame before the text so a page can put artwork behind its list.
	var draw := Callable()

	## menu.c menu_page_add_button()
	func add_button(entry_data: int, entry_text: String, select: Callable) -> Entry:
		var entry := Entry.new()
		entry.type = Entry.BUTTON
		entry.data = entry_data
		entry.text = entry_text
		entry.select = select
		entries.append(entry)
		return entry

	## menu.c menu_page_add_toggle(). `entry_data` is the index of the option
	## that starts out selected.
	func add_toggle(entry_data: int, entry_text: String, entry_options: PackedStringArray, select: Callable) -> Entry:
		var entry := Entry.new()
		entry.type = Entry.TOGGLE
		entry.data = entry_data
		entry.text = entry_text
		entry.options = entry_options
		entry.select = select
		entries.append(entry)
		return entry


## Scene ui_cancel falls back to once page 0 is showing. "" keeps the player
## where they are, like menu_pop() at index 0.
var back_scene := ""

var _pages: Array = []


func _ready() -> void:
	if _wants_backdrop():
		MenuBackdrop.attach(self)
		# A CanvasItem paints itself before its children, so the backdrop has to
		# be pushed behind this node's _draw() or it would cover the page.
		var backdrop := get_node_or_null("WipeoutBackdrop") as CanvasItem
		if backdrop != null:
			backdrop.z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


## Subclass hook: push the scene's first page, as page_*_init() does.
func _build() -> void:
	pass


## Whether main_menu.c's wipeout1.tim background belongs behind this menu. The
## in-race menus draw over the track instead.
func _wants_backdrop() -> bool:
	return true


# -----------------------------------------------------------------------------
# Page stack

## menu.c menu_push()
func push_page(page_title: String, draw_func := Callable()) -> Page:
	var page := Page.new()
	page.layout_flags = VERTICAL | ALIGN_CENTER
	page.title = page_title
	page.title_anchor = MIDDLE_CENTER
	page.items_anchor = MIDDLE_CENTER
	page.draw = draw_func
	_pages.append(page)
	queue_redraw()
	return page


## menu.c menu_confirm(): a horizontal yes/no page, starting on "no".
func push_confirm(page_title: String, subtitle: String, yes: String, no: String, confirm_func: Callable) -> Page:
	var page := Page.new()
	page.layout_flags = HORIZONTAL
	page.title = page_title
	page.subtitle = subtitle
	page.title_anchor = MIDDLE_CENTER
	page.items_anchor = MIDDLE_CENTER
	page.add_button(1, yes, confirm_func)
	page.add_button(0, no, confirm_func)
	page.index = 1
	_pages.append(page)
	queue_redraw()
	return page


## menu.c menu_pop(). Page 0 is the scene itself and cannot be popped.
func pop_page() -> void:
	if _pages.size() <= 1:
		return
	_pages.pop_back()
	queue_redraw()


## menu.c menu_reset() followed by the page_*_init() that repopulates the menu.
## The in-race menus rebuild themselves like this every time they open.
func reset_pages() -> void:
	_pages.clear()
	_build()
	queue_redraw()


## menu.c menu_reset() on its own, for the pages that reset the stack so it
## *cannot* be walked back (game_over_menu_init, page_hall_of_fame_init: "Can't
## go back!") and push their own replacement instead of _build()'s.
func clear_pages() -> void:
	_pages.clear()
	queue_redraw()


func current_page() -> Page:
	if _pages.is_empty():
		return null
	return _pages[-1]


func page_depth() -> int:
	return _pages.size()


# -----------------------------------------------------------------------------
# Drawing

## The selected entry blinks, so the page redraws every frame.
func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var page := current_page()
	if page == null:
		return
	var scale := _ui_scale()

	if page.draw.is_valid():
		page.draw.call(selected_data(), scale)

	if page.layout_flags & HORIZONTAL:
		_draw_horizontal(page, scale)
	else:
		_draw_vertical(page, scale)


## The `data` of the highlighted entry, which menu.c hands to the draw_func.
func selected_data() -> int:
	var page := current_page()
	if page == null or page.entries.is_empty():
		return 0
	var entry: Entry = page.entries[page.index]
	return entry.data


func _draw_horizontal(page: Page, scale: float) -> void:
	var pos := Vector2(0.0, -20.0)
	_text_centered(page.title, page.title_anchor, pos, WipeoutUI.SIZE_8, WipeoutUI.COLOR_DEFAULT, scale)
	if page.subtitle != "":
		pos.y += 12.0
		_text_centered(page.subtitle, page.title_anchor, pos, WipeoutUI.SIZE_8, WipeoutUI.COLOR_DEFAULT, scale)
	pos.y += 16.0

	var blinking := _blink()
	for i in page.entries.size():
		var entry: Entry = page.entries[i]
		var color := WipeoutUI.COLOR_DEFAULT
		if i == page.index and blinking:
			color = WipeoutUI.COLOR_ACCENT
		pos.x = _horizontal_item_x(i)
		_text_centered(entry.text, page.items_anchor, pos, WipeoutUI.SIZE_16, color, scale)


func _draw_vertical(page: Page, scale: float) -> void:
	var title_pos := _layout_title_pos(page)
	var items_pos := _layout_items_pos(page)
	var centered := page.layout_flags & ALIGN_CENTER != 0

	if centered:
		_text_centered(page.title, page.title_anchor, title_pos, WipeoutUI.SIZE_12, WipeoutUI.COLOR_ACCENT, scale)
	else:
		_text(page.title, page.title_anchor, title_pos, WipeoutUI.SIZE_12, WipeoutUI.COLOR_ACCENT, scale)

	var blinking := _blink()
	for i in page.entries.size():
		var entry: Entry = page.entries[i]
		var color := WipeoutUI.COLOR_DEFAULT
		if i == page.index and blinking:
			color = WipeoutUI.COLOR_ACCENT

		if centered:
			_text_centered(entry.text, page.items_anchor, items_pos, WipeoutUI.SIZE_8, color, scale)
		else:
			_text(entry.text, page.items_anchor, items_pos, WipeoutUI.SIZE_8, color, scale)

		if entry.type == Entry.TOGGLE:
			# The chosen option sits flush with the right edge of the block.
			var option := _option_text(entry)
			var toggle_pos := items_pos
			toggle_pos.x += page.block_width - WipeoutUI.text_width(option, WipeoutUI.SIZE_8)
			_text(option, page.items_anchor, toggle_pos, WipeoutUI.SIZE_8, color, scale)

		items_pos.y += ITEM_STEP


func _option_text(entry: Entry) -> String:
	if entry.options.is_empty():
		return ""
	return entry.options[clampi(entry.data, 0, entry.options.size() - 1)]


## menu.c centres a page that is not MENU_FIXED on its own height.
func _layout_title_pos(page: Page) -> Vector2:
	if page.layout_flags & FIXED:
		return page.title_pos
	return Vector2(0.0, -_auto_height(page) / 2.0)


func _layout_items_pos(page: Page) -> Vector2:
	if page.layout_flags & FIXED:
		return page.items_pos
	return Vector2(0.0, -_auto_height(page) / 2.0 + 20.0)


func _auto_height(page: Page) -> float:
	return 20.0 + page.entries.size() * ITEM_STEP


## menu.c puts the first horizontal entry left of centre and the second right.
func _horizontal_item_x(index: int) -> float:
	return -50.0 if index == 0 else 60.0


## Adds an off-screen 3D turntable (menu_model_preview.gd) as a child of this
## menu. Subclasses call this once from _build() to get something to
## show_model() and _draw_model_preview() from their draw_func, standing in
## for main_menu.c's draw_model() calls mixed into the original's 2D pass.
func _add_model_preview() -> MenuModelPreview:
	return MenuModelPreview.attach(self)


## Blits `preview`'s current frame `preview_size` unscaled pixels wide/tall,
## centred `pos` units from `anchor` -- the same convention circuit_menu.gd
## and pilot_menu.gd use for their 2D artwork.
func _draw_model_preview(preview: MenuModelPreview, anchor: Vector2, pos: Vector2, preview_size: Vector2, scale: float) -> void:
	if preview == null:
		return
	var scaled_size := preview_size * MODEL_PREVIEW_SCALE
	var top_left := _anchored(anchor, pos - scaled_size * 0.5, scale)
	draw_texture_rect(preview.get_texture(), Rect2(top_left, scaled_size * scale), false)


func _text(text: String, anchor: Vector2, offset: Vector2, size: int, color: Color, scale: float) -> void:
	WipeoutUI.draw_text(self, text, _anchored(anchor, offset, scale), size, color, scale)


func _text_centered(text: String, anchor: Vector2, offset: Vector2, size: int, color: Color, scale: float) -> void:
	WipeoutUI.draw_text_centered(self, text, _anchored(anchor, offset, scale), size, color, scale)


## ui.c's ui_scaled_pos(): an anchor on the screen plus an offset in unscaled
## units. Menus fill the viewport, so this Control's size is the screen size.
func _anchored(anchor: Vector2, offset: Vector2, scale: float) -> Vector2:
	return Vector2(
		floorf(size.x * anchor.x) + offset.x * scale,
		floorf(size.y * anchor.y) + offset.y * scale
	)


## game.c's game_update(): one integer step per 360 (or 240) pixels of height.
func _ui_scale() -> float:
	var height := int(size.y)
	var scale := height / 360 if height >= 720 else height / 240
	return float(maxi(1, scale))


## menu.c's blink(): the highlight flips 30 times per second.
func _blink() -> bool:
	return fmod(Time.get_ticks_msec() / 1000.0, 1.0 / 15.0) < 1.0 / 30.0


# -----------------------------------------------------------------------------
# Input

func _unhandled_input(event: InputEvent) -> void:
	# A hidden menu (the pause page during a race) must not steal input.
	if not is_visible_in_tree():
		return
	var page := current_page()
	if page == null:
		return

	if not page.entries.is_empty():
		var step := 0
		if page.layout_flags & HORIZONTAL:
			if event.is_action_pressed("ui_left"):
				step = -1
			elif event.is_action_pressed("ui_right"):
				step = 1
		else:
			if event.is_action_pressed("ui_up"):
				step = -1
			elif event.is_action_pressed("ui_down"):
				step = 1
		if step != 0:
			get_viewport().set_input_as_handled()
			move_selection(step)
			return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()
		return

	if page.entries.is_empty():
		return

	# The event is marked handled before the entry runs: a select_func that
	# changes scene takes this menu out of the tree, and get_viewport() would
	# then be null.
	var entry: Entry = page.entries[page.index]
	if entry.type == Entry.TOGGLE:
		# Left/right are free on a vertical page, so they cycle the options.
		if event.is_action_pressed("ui_left"):
			get_viewport().set_input_as_handled()
			cycle_entry(entry, -1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			cycle_entry(entry, 1)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		activate_entry(entry)


## The original pages are keyboard/pad only; the mouse is kept working because
## every menu in this port used to be clickable. Right-click stands in for the
## back button the original never draws.
func _gui_input(event: InputEvent) -> void:
	var page := current_page()
	if page == null:
		return

	if event is InputEventMouseMotion:
		var hovered := entry_at((event as InputEventMouseMotion).position)
		if hovered >= 0 and hovered != page.index:
			page.index = hovered
			GameAudio.play_move()
		return

	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		back()
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return

	var clicked := entry_at(button.position)
	if clicked < 0:
		return
	page.index = clicked
	# Claimed before the entry runs, for the same reason as in _unhandled_input.
	accept_event()
	var entry: Entry = page.entries[clicked]
	if entry.type == Entry.TOGGLE:
		cycle_entry(entry, 1)
	else:
		activate_entry(entry)


func move_selection(step: int) -> void:
	var page := current_page()
	if page == null or page.entries.is_empty():
		return
	page.index = wrapi(page.index + step, 0, page.entries.size())
	GameAudio.play_move()


func activate_entry(entry: Entry) -> void:
	if not entry.select.is_valid():
		return
	GameAudio.play_select()
	entry.select.call(entry.data)


func cycle_entry(entry: Entry, step: int) -> void:
	if entry.options.is_empty():
		return
	entry.data = wrapi(entry.data + step, 0, entry.options.size())
	GameAudio.play_select()
	if entry.select.is_valid():
		entry.select.call(entry.data)


## menu.c pops a page on back; page 0 leaves for `back_scene` instead.
func back() -> void:
	if _pages.size() > 1:
		GameAudio.play_select()
		pop_page()
		return
	if back_scene == "":
		return
	GameAudio.play_select()
	get_tree().change_scene_to_file(back_scene)


## Index of the entry under `point` in this Control's coordinates, or -1.
func entry_at(point: Vector2) -> int:
	var page := current_page()
	if page == null:
		return -1
	var scale := _ui_scale()
	for i in page.entries.size():
		if entry_rect(i, scale).has_point(point):
			return i
	return -1


## Hit box of entry `i`, laid out exactly like _draw_horizontal/_draw_vertical.
func entry_rect(i: int, scale: float) -> Rect2:
	var page := current_page()
	if page == null or i < 0 or i >= page.entries.size():
		return Rect2()
	var entry: Entry = page.entries[i]

	if page.layout_flags & HORIZONTAL:
		var height := WipeoutUI.text_height(WipeoutUI.SIZE_16) * scale
		var width := WipeoutUI.text_width(entry.text, WipeoutUI.SIZE_16) * scale
		var pos := Vector2(_horizontal_item_x(i), -20.0)
		if page.subtitle != "":
			pos.y += 12.0
		pos.y += 16.0
		var origin := _anchored(page.items_anchor, pos, scale)
		return Rect2(origin.x - width * 0.5, origin.y, width, height)

	var items_pos := _layout_items_pos(page)
	items_pos.y += i * ITEM_STEP
	var origin_v := _anchored(page.items_anchor, items_pos, scale)
	var row_height := WipeoutUI.text_height(WipeoutUI.SIZE_8) * scale
	if page.layout_flags & ALIGN_CENTER:
		var text_width := WipeoutUI.text_width(entry.text, WipeoutUI.SIZE_8) * scale
		return Rect2(origin_v.x - text_width * 0.5, origin_v.y, text_width, row_height)
	# Left-aligned pages run the whole block width so a toggle's option is
	# clickable too.
	return Rect2(origin_v.x, origin_v.y, page.block_width * scale, row_height)
