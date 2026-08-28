extends RefCounted
class_name WipeoutUI

## Bitmap text drawing ported from src/wipeout/ui.c. The three DRFONTS glyph
## atlases (drfonts.cmp entries 0/1/2, exported here as drfonts_00/01/02.png)
## are drawn glyph by glyph with the exact offset/width tables from ui.c's
## `char_set`, so in-race text keeps the original kerning and pixel look instead
## of falling back to Godot's default vector font.
##
## Glyph order matches ui.c's char_to_glyph_index(): 0-25 are 'A'-'Z', 26-35 are
## '0'-'9', 36 is ":" (encoded as 'e' in the original's time strings) and 37 is
## "." (encoded as 'f'). Callers pass real ':' / '.' characters; text is
## uppercased before lookup since the atlases only carry capitals.
##
## ui.c's rgba(128,128,128) means *full* brightness (the PSX-style renderer
## modulates textures at 2x), so UI_COLOR_* is doubled into the Color constants
## below.

enum {
	SIZE_16 = 0, ## ui.h UI_SIZE_16
	SIZE_12 = 1, ## ui.h UI_SIZE_12
	SIZE_8 = 2, ## ui.h UI_SIZE_8
}

const COLOR_DEFAULT := Color(1.0, 1.0, 1.0) # ui.h UI_COLOR_DEFAULT rgba(128,128,128)
const COLOR_ACCENT := Color(246.0 / 255.0, 196.0 / 255.0, 24.0 / 255.0) # ui.h UI_COLOR_ACCENT rgba(123,98,12)

## ui_char_width(): a space is a flat 8px advance in every size, with no glyph.
const SPACE_WIDTH := 8.0

const ATLAS_PATHS: Array[String] = [
	"res://assets/ui/drfonts/drfonts_00.png",
	"res://assets/ui/drfonts/drfonts_01.png",
	"res://assets/ui/drfonts/drfonts_02.png",
]

## char_set[*].height — also the source rect height of every glyph.
const HEIGHTS: Array[float] = [16.0, 12.0, 8.0]

## Each entry is (atlas x, atlas y, glyph width / advance), straight from
## char_set[UI_SIZE_16].glyphs in ui.c.
const GLYPHS_16: Array[Vector3i] = [
	Vector3i(0, 0, 25), Vector3i(25, 0, 24), Vector3i(49, 0, 17), Vector3i(66, 0, 24),
	Vector3i(90, 0, 24), Vector3i(114, 0, 17), Vector3i(131, 0, 25), Vector3i(156, 0, 18),
	Vector3i(174, 0, 7), Vector3i(181, 0, 17), Vector3i(0, 16, 17), Vector3i(17, 16, 17),
	Vector3i(34, 16, 28), Vector3i(62, 16, 17), Vector3i(79, 16, 24), Vector3i(103, 16, 24),
	Vector3i(127, 16, 26), Vector3i(153, 16, 24), Vector3i(177, 16, 18), Vector3i(195, 16, 17),
	Vector3i(0, 32, 17), Vector3i(17, 32, 17), Vector3i(34, 32, 29), Vector3i(63, 32, 24),
	Vector3i(87, 32, 17), Vector3i(104, 32, 18), Vector3i(122, 32, 24), Vector3i(146, 32, 10),
	Vector3i(156, 32, 18), Vector3i(174, 32, 17), Vector3i(191, 32, 18), Vector3i(0, 48, 18),
	Vector3i(18, 48, 18), Vector3i(36, 48, 18), Vector3i(54, 48, 22), Vector3i(76, 48, 25),
	Vector3i(101, 48, 7), Vector3i(108, 48, 7), Vector3i(198, 0, 0), Vector3i(198, 0, 0),
]

## char_set[UI_SIZE_12].glyphs
const GLYPHS_12: Array[Vector3i] = [
	Vector3i(0, 0, 19), Vector3i(19, 0, 19), Vector3i(38, 0, 14), Vector3i(52, 0, 19),
	Vector3i(71, 0, 19), Vector3i(90, 0, 13), Vector3i(103, 0, 19), Vector3i(122, 0, 14),
	Vector3i(136, 0, 6), Vector3i(142, 0, 13), Vector3i(155, 0, 14), Vector3i(169, 0, 14),
	Vector3i(0, 12, 22), Vector3i(22, 12, 14), Vector3i(36, 12, 19), Vector3i(55, 12, 18),
	Vector3i(73, 12, 20), Vector3i(93, 12, 19), Vector3i(112, 12, 15), Vector3i(127, 12, 14),
	Vector3i(141, 12, 13), Vector3i(154, 12, 13), Vector3i(167, 12, 22), Vector3i(0, 24, 19),
	Vector3i(19, 24, 13), Vector3i(32, 24, 14), Vector3i(46, 24, 19), Vector3i(65, 24, 8),
	Vector3i(73, 24, 15), Vector3i(88, 24, 13), Vector3i(101, 24, 14), Vector3i(115, 24, 15),
	Vector3i(130, 24, 14), Vector3i(144, 24, 15), Vector3i(159, 24, 18), Vector3i(177, 24, 19),
	Vector3i(196, 24, 5), Vector3i(201, 24, 5), Vector3i(183, 0, 0), Vector3i(183, 0, 0),
]

## char_set[UI_SIZE_8].glyphs
const GLYPHS_8: Array[Vector3i] = [
	Vector3i(0, 0, 13), Vector3i(13, 0, 13), Vector3i(26, 0, 10), Vector3i(36, 0, 13),
	Vector3i(49, 0, 13), Vector3i(62, 0, 9), Vector3i(71, 0, 13), Vector3i(84, 0, 10),
	Vector3i(94, 0, 4), Vector3i(98, 0, 9), Vector3i(107, 0, 10), Vector3i(117, 0, 10),
	Vector3i(127, 0, 16), Vector3i(143, 0, 10), Vector3i(153, 0, 13), Vector3i(166, 0, 13),
	Vector3i(179, 0, 14), Vector3i(0, 8, 13), Vector3i(13, 8, 10), Vector3i(23, 8, 9),
	Vector3i(32, 8, 9), Vector3i(41, 8, 9), Vector3i(50, 8, 16), Vector3i(66, 8, 14),
	Vector3i(80, 8, 9), Vector3i(89, 8, 10), Vector3i(99, 8, 13), Vector3i(112, 8, 6),
	Vector3i(118, 8, 11), Vector3i(129, 8, 10), Vector3i(139, 8, 10), Vector3i(149, 8, 11),
	Vector3i(160, 8, 10), Vector3i(170, 8, 10), Vector3i(180, 8, 12), Vector3i(192, 8, 14),
	Vector3i(206, 8, 4), Vector3i(210, 8, 4), Vector3i(193, 0, 0), Vector3i(193, 0, 0),
]

const GLYPHS := [GLYPHS_16, GLYPHS_12, GLYPHS_8]

static var _atlases: Array[Texture2D] = []


## Lazily loaded drfonts atlas for one UI size. Returns null if the exported
## PNG is missing, in which case every draw call becomes a no-op.
static func atlas(size: int) -> Texture2D:
	if _atlases.is_empty():
		_atlases.resize(ATLAS_PATHS.size())
		for i in ATLAS_PATHS.size():
			if ResourceLoader.exists(ATLAS_PATHS[i]):
				_atlases[i] = load(ATLAS_PATHS[i]) as Texture2D
			else:
				push_warning("WipeoutUI: missing font atlas %s" % ATLAS_PATHS[i])
	return _atlases[clampi(size, 0, _atlases.size() - 1)]


## ui.c char_to_glyph_index(), plus the ':' / '.' aliases the original smuggles
## in as 'e' / 'f'. Returns -1 for characters the atlases don't carry.
static func glyph_index(character: String) -> int:
	if character.is_empty():
		return -1
	var code := character.unicode_at(0)
	if code >= 48 and code <= 57: # '0'..'9'
		return code - 48 + 26
	if code == 58: # ':'
		return 36
	if code == 46: # '.'
		return 37
	if code >= 65 and code <= 90: # 'A'..'Z'
		return code - 65
	return -1


static func char_width(character: String, size: int) -> float:
	if character == " ":
		return SPACE_WIDTH
	var glyphs: Array = GLYPHS[clampi(size, 0, GLYPHS.size() - 1)]
	var index := glyph_index(character.to_upper())
	if index < 0 or index >= glyphs.size():
		return 0.0
	return float((glyphs[index] as Vector3i).z)


## ui_text_width(): unscaled advance of `text`, in source-atlas pixels.
static func text_width(text: String, size: int) -> float:
	var glyphs: Array = GLYPHS[clampi(size, 0, GLYPHS.size() - 1)]
	var upper := text.to_upper()
	var width := 0.0
	for i in upper.length():
		var character := upper[i]
		if character == " ":
			width += SPACE_WIDTH
			continue
		var index := glyph_index(character)
		if index < 0 or index >= glyphs.size():
			continue
		width += float((glyphs[index] as Vector3i).z)
	return width


static func text_height(size: int) -> float:
	return HEIGHTS[clampi(size, 0, HEIGHTS.size() - 1)]


## ui_draw_text(). `scale` stands in for ui.c's global ui_scale.
static func draw_text(canvas: CanvasItem, text: String, pos: Vector2, size: int, color: Color, scale: float) -> void:
	if canvas == null:
		return
	var clamped := clampi(size, 0, GLYPHS.size() - 1)
	var texture := atlas(clamped)
	if texture == null:
		return
	var glyphs: Array = GLYPHS[clamped]
	var height: float = HEIGHTS[clamped]
	var upper := text.to_upper()
	var x := pos.x
	for i in upper.length():
		var character := upper[i]
		if character == " ":
			x += SPACE_WIDTH * scale
			continue
		var index := glyph_index(character)
		if index < 0 or index >= glyphs.size():
			continue
		var glyph: Vector3i = glyphs[index]
		if glyph.z <= 0:
			continue
		var width := float(glyph.z)
		canvas.draw_texture_rect_region(
			texture,
			Rect2(x, pos.y, width * scale, height * scale),
			Rect2(float(glyph.x), float(glyph.y), width, height),
			color
		)
		x += width * scale


## ui_draw_text_centered()
static func draw_text_centered(canvas: CanvasItem, text: String, pos: Vector2, size: int, color: Color, scale: float) -> void:
	draw_text(canvas, text, Vector2(pos.x - text_width(text, size) * scale * 0.5, pos.y), size, color, scale)


## ui_draw_time()'s "MM:SS.T" layout, with real ':' / '.' characters.
static func format_time(time: float) -> String:
	var msec := int(maxf(time, 0.0) * 1000.0)
	var tenths := (msec / 100) % 10
	var secs := (msec / 1000) % 60
	var mins := (msec / 60000) % 100
	return "%02d:%02d.%d" % [mins, secs, tenths]


static func draw_time(canvas: CanvasItem, time: float, pos: Vector2, size: int, color: Color, scale: float) -> void:
	draw_text(canvas, format_time(time), pos, size, color, scale)
