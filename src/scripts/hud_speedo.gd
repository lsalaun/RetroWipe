extends Control

## In-race speedo facia + bars from src/wipeout/hud.c (speedo.tim 128x32).

const FACIA := "res://assets/ui/speedo.png"
const SKEW := 2.0
const LOGICAL_W := 128.0
const LOGICAL_H := 32.0
const SPEED_FULL := 90.0
const THRUST_COLOR := Color(1.0, 0.0, 0.0, 0.5)
## hud.c: facia at (-141,-45), bars at (-141,-40) — same X, bars 5px lower.
const BAR_ORIGIN := Vector2(0.0, 5.0)

const BARS: Array[Dictionary] = [
	{"x": 6.0, "y": 12.0, "h": 10.0, "c": Color(66.0 / 255.0, 16.0 / 255.0, 49.0 / 255.0)},
	{"x": 13.0, "y": 12.0, "h": 10.0, "c": Color(115.0 / 255.0, 33.0 / 255.0, 90.0 / 255.0)},
	{"x": 20.0, "y": 12.0, "h": 10.0, "c": Color(132.0 / 255.0, 58.0 / 255.0, 164.0 / 255.0)},
	{"x": 27.0, "y": 12.0, "h": 10.0, "c": Color(99.0 / 255.0, 90.0 / 255.0, 197.0 / 255.0)},
	{"x": 34.0, "y": 12.0, "h": 10.0, "c": Color(74.0 / 255.0, 148.0 / 255.0, 181.0 / 255.0)},
	{"x": 41.0, "y": 12.0, "h": 10.0, "c": Color(66.0 / 255.0, 173.0 / 255.0, 115.0 / 255.0)},
	{"x": 50.0, "y": 10.0, "h": 12.0, "c": Color(99.0 / 255.0, 206.0 / 255.0, 58.0 / 255.0)},
	{"x": 59.0, "y": 8.0, "h": 12.0, "c": Color(189.0 / 255.0, 206.0 / 255.0, 41.0 / 255.0)},
	{"x": 69.0, "y": 5.0, "h": 13.0, "c": Color(247.0 / 255.0, 140.0 / 255.0, 33.0 / 255.0)},
	{"x": 81.0, "y": 2.0, "h": 15.0, "c": Color(255.0 / 255.0, 197.0 / 255.0, 49.0 / 255.0)},
	{"x": 95.0, "y": 1.0, "h": 16.0, "c": Color(255.0 / 255.0, 222.0 / 255.0, 115.0 / 255.0)},
	{"x": 110.0, "y": 1.0, "h": 16.0, "c": Color(255.0 / 255.0, 239.0 / 255.0, 181.0 / 255.0)},
	{"x": 126.0, "y": 1.0, "h": 16.0, "c": Color(1.0, 1.0, 1.0)},
]

var _speed_fill: float = 0.0
var _thrust_fill: float = 0.0
var _ship: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var facia := get_node_or_null("Facia") as TextureRect
	if facia != null and facia.texture == null and ResourceLoader.exists(FACIA):
		facia.texture = load(FACIA) as Texture2D


func _process(_delta: float) -> void:
	_ship = _find_player()
	_speed_fill = 0.0
	_thrust_fill = 0.0
	if _ship != null:
		var speed := 0.0
		if "velocity" in _ship:
			speed = (_ship.velocity as Vector3).length()
		_speed_fill = clampf(speed / SPEED_FULL * 13.0, 0.0, 13.0)
		var thrust := 0.0
		var thrust_max := 1.0
		if "thrust_mag" in _ship:
			thrust = float(_ship.thrust_mag)
		if "thrust_max" in _ship:
			thrust_max = maxf(float(_ship.thrust_max), 1.0)
		_thrust_fill = clampf(thrust / thrust_max * 13.0, 0.0, 13.0)
	queue_redraw()


func _draw() -> void:
	_draw_speedo_bars(_thrust_fill, THRUST_COLOR)
	_draw_speedo_bars(_speed_fill, Color(0.0, 0.0, 0.0, 0.0))


func _find_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(&"ships"):
		if node.get("is_player_controlled") == true:
			return node
	return null


func _draw_speedo_bars(fill: float, override_col: Color) -> void:
	if fill <= 0.0:
		return
	if fill - floorf(fill) > 0.9:
		fill = ceilf(fill)
	fill = minf(fill, 13.0)
	var bars := int(fill)
	for i in range(1, bars):
		_draw_speedo_bar(BARS[i - 1], BARS[i], 1.0, override_col)
	if bars > 12:
		return
	var last_frac := fill - float(bars) + 0.1
	if last_frac <= 0.0:
		return
	last_frac = minf(last_frac, 1.0)
	var last_bar := 1 if bars == 0 else bars
	_draw_speedo_bar(BARS[last_bar - 1], BARS[last_bar], last_frac, override_col)


func _draw_speedo_bar(a: Dictionary, b: Dictionary, f: float, override_col: Color) -> void:
	var sx := size.x / LOGICAL_W
	var sy := size.y / LOGICAL_H
	var origin := Vector2(BAR_ORIGIN.x * sx, BAR_ORIGIN.y * sy)
	var left_color: Color = override_col if override_col.a > 0.0 else a["c"]
	var right_color: Color = override_col
	if override_col.a <= 0.0:
		var ca: Color = a["c"]
		var cb: Color = b["c"]
		right_color = ca.lerp(cb, f)
	var ah := float(a["h"])
	var bh := float(b["h"])
	var right_h := lerpf(ah, bh, f)
	var ax := float(a["x"])
	var ay := float(a["y"])
	var bx := float(b["x"])
	var by := float(b["y"])
	var top_left := Vector2((ax + 1.0) * sx, ay * sy) + origin
	var bottom_left := Vector2((ax + 1.0 - ah / SKEW) * sx, (ay + ah) * sy) + origin
	var top_right := Vector2(lerpf(ax + 1.0, bx, f) * sx, lerpf(ay, by, f) * sy) + origin
	var bottom_right := Vector2(top_right.x - right_h / SKEW * sx, top_right.y + right_h * sy)
	var z := Vector2.ZERO
	draw_primitive(
		PackedVector2Array([bottom_left, top_right, top_left]),
		PackedColorArray([left_color, right_color, left_color]),
		PackedVector2Array([z, z, z])
	)
	draw_primitive(
		PackedVector2Array([bottom_right, top_right, bottom_left]),
		PackedColorArray([right_color, right_color, left_color]),
		PackedVector2Array([z, z, z])
	)
