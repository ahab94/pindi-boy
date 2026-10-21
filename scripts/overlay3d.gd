extends Control
## Floating words over the 3D street: combo labels, "+VIEWS", crash lines
## and speech bubbles. They're 2D text placed where a 3D point lands on
## screen (Camera3D.unproject_position), so they stay crisp at any size.

var view
var ride


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	size = get_viewport_rect().size


func _draw() -> void:
	if ride == null or view == null:
		return
	var font := ThemeDB.fallback_font
	var portrait := size.y > size.x
	for pp in ride.popups:
		var age: float = ride.t - float(pp.t0)
		var rel: bool = pp.get("rel", false)
		var px: float = float(pp.x) + (float(ride.x) if rel else 0.0)
		var pd: float = float(ride.d) if rel else float(pp.d)
		if view.behind_camera(px, pd, float(pp.h)):
			continue
		var sp: Vector2 = view.screen(px, pd, float(pp.h) + age * 1.4)
		var grow := minf(1.0, age * 8.0)
		var fs := int((28.0 if not portrait else 30.0) * (0.6 + 0.4 * grow))
		var msg := String(pp.text)
		var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col: Color = pp.col
		col.a = clampf(1.4 - age, 0.0, 1.0)
		var at := sp - Vector2(tw / 2.0, 0)
		draw_string_outline(font, at, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0.1, 0.05, 0.05, col.a))
		draw_string(font, at, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	for b in ride.bubbles:
		var age: float = ride.t - float(b.t0)
		if view.behind_camera(float(b.x), float(b.d), float(b.h)):
			continue
		var sp: Vector2 = view.screen(float(b.x), float(b.d), float(b.h) + 0.4)
		var fs := 22 if not portrait else 24
		var msg := String(b.text)
		var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pop := minf(1.0, age * 10.0)
		var box := Rect2(sp + Vector2(-tw / 2.0 - 10.0, -fs - 24.0), Vector2(tw + 20.0, fs + 14.0))
		box = Rect2(box.get_center() - box.size * pop / 2.0, box.size * pop)
		var a := minf(1.0, clampf(1.6 - age, 0.0, 1.0) * 2.0)
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-7, -10), sp + Vector2(7, -10), sp + Vector2(0, 2)]), Color(1, 1, 1, a))
		draw_rect(box, Color(1, 1, 1, a))
		draw_rect(box, Color(0.1, 0.1, 0.1, a), false, 2.0)
		if pop >= 1.0:
			draw_string(font, box.position + Vector2(10, fs + 3), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.1, 0.1, a))
