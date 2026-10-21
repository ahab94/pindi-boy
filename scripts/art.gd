extends RefCounted
## Every character and vehicle, drawn with Godot's immediate-mode 2D calls
## (draw_colored_polygon, draw_line, draw_circle) from inside view.gd's
## _draw(). Nothing is an image file.
##
## Two ways of placing things:
##   - The pen: a little local frame in metres with y up. `o` is where (0,0)
##     lands on screen, `s` is pixels per metre, `rot` tilts it (a wheelie
##     is the whole bike+rider frame turned about the rear tyre) and `flip`
##     mirrors it for things facing left. Profiles (bikes, people, animals)
##     are drawn with the pen.
##   - World boxes: view.P(x, d, h) projects a world point, and box() draws
##     the three faces you can see from this angle (front, top, right side).
##     Vehicles are boxes with pen-drawn details on their near face.

var c: CanvasItem            # the node we draw into (view.gd)
var view                     # for P()
var o := Vector2.ZERO
var s := 40.0
var rot := 0.0
var flip := 1.0
var sy := 1.0                # squash (a bike lying on its side)
## Fidelity knobs. ink: outline width in pixels (0 = none). shade: how much
## lighter the top of each shape is than its bottom, like light from above.
var ink := 0.0
var shade := 0.0
var ink_col := Color(0.1, 0.06, 0.05, 0.85)

const SKIN := Color(0.78, 0.55, 0.38)
const SKIN_DARK := Color(0.62, 0.42, 0.28)
const HAIR := Color(0.07, 0.06, 0.06)
const KAMEEZ := Color(0.42, 0.72, 0.95)
const KAMEEZ_DARK := Color(0.30, 0.55, 0.78)
const TYRE := Color(0.1, 0.1, 0.11)
const CHROME := Color(0.82, 0.84, 0.88)
const OUTLINE := Color(0.12, 0.08, 0.06, 0.9)


# ---------------------------------------------------------------- the pen

func pen(origin: Vector2, scale: float, rotation := 0.0, mirror := 1.0) -> void:
	o = origin
	s = scale
	rot = rotation
	flip = mirror
	sy = 1.0


func p(x: float, y: float) -> Vector2:
	var lx := x * flip
	var ly := y * sy
	var cs := cos(rot * flip)
	var sn := sin(rot * flip)
	return o + Vector2(lx * cs - ly * sn, -(lx * sn + ly * cs)) * s


func poly(pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for q in pts:
		out.append(p(q.x, q.y))
	_fill(out, col)


func _fill(out: PackedVector2Array, col: Color) -> void:
	if out.size() < 3:
		return
	# Godot refuses polygons with no area, so skip slivers.
	var area := 0.0
	for i in out.size():
		var a := out[i]
		var b := out[(i + 1) % out.size()]
		area += a.x * b.y - b.x * a.y
	if absf(area) < 1.0:
		return
	# A flapping wing or a wind-blown kameez tail can fold over itself, and
	# Godot can't fill a self-crossing outline: skip those frames' shape.
	if out.size() > 3 and Geometry2D.triangulate_polygon(out).is_empty():
		return
	if shade > 0.0:
		# Per-vertex colours: Godot blends them across the polygon, which
		# gives a cheap top-lit gradient.
		var top := INF
		var bot := -INF
		for q in out:
			top = minf(top, q.y)
			bot = maxf(bot, q.y)
		var span := maxf(1.0, bot - top)
		var cols := PackedColorArray()
		for q in out:
			var f := (q.y - top) / span
			cols.append(col.lightened(shade * (1.0 - f)).darkened(shade * 0.8 * f))
		c.draw_polygon(out, cols)
	else:
		c.draw_colored_polygon(out, col)
	if ink > 0.0:
		var ring := out.duplicate()
		ring.append(out[0])
		c.draw_polyline(ring, ink_col, ink, true)


func line(x0: float, y0: float, x1: float, y1: float, w: float, col: Color) -> void:
	c.draw_line(p(x0, y0), p(x1, y1), col, maxf(1.0, w * s), true)


## A limb: a thick line with round ends.
func limb(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var pa := p(a.x, a.y)
	var pb := p(b.x, b.y)
	var px := maxf(1.0, w * s)
	if ink > 0.0:
		c.draw_line(pa, pb, ink_col, px + ink * 2.0)
		c.draw_circle(pa, px / 2.0 + ink, ink_col)
		c.draw_circle(pb, px / 2.0 + ink, ink_col)
	c.draw_line(pa, pb, col, px)
	c.draw_circle(pa, px / 2.0, col)
	c.draw_circle(pb, px / 2.0, col)
	if shade > 0.0 and px > 4.0:
		# A highlight along the lit edge of the limb.
		var n := (pb - pa).orthogonal().normalized()
		if n.y > 0.0:
			n = -n
		c.draw_line(pa + n * px * 0.22, pb + n * px * 0.22, col.lightened(shade * 1.4), px * 0.3)


func circle(x: float, y: float, r: float, col: Color) -> void:
	if r * s < 0.5:
		return
	var at := p(x, y)
	if ink > 0.0 and r * s > 3.0:
		c.draw_circle(at, r * s + ink, ink_col)
	c.draw_circle(at, r * s, col)
	if shade > 0.0 and r * s > 4.0:
		c.draw_circle(at + Vector2(-0.3, -0.35) * r * s, r * s * 0.45, Color(col.lightened(shade * 1.5), 0.55))


func ring(x: float, y: float, r: float, w: float, col: Color) -> void:
	c.draw_arc(p(x, y), r * s, 0.0, TAU, 24, col, maxf(1.0, w * s), true)


func rect(x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	poly([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], col)


func ellipse(x: float, y: float, rx: float, ry: float, col: Color, n := 14) -> void:
	var pts: Array = []
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(x + cos(a) * rx, y + sin(a) * ry))
	poly(pts, col)


func text(x: float, y: float, msg: String, size: float, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var px := int(maxf(6.0, size * s))
	var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(font, p(x, y) - Vector2(w / 2.0, -px * 0.35), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


# ---------------------------------------------------------------- world boxes

func P(x: float, d: float, h: float) -> Vector2:
	return view.P(x, d, h)


## The three faces of an axis-aligned box that face the camera.
func box(x0: float, x1: float, d0: float, d1: float, h0: float, h1: float, col: Color, top_col = null) -> void:
	var top: Color = top_col if top_col != null else col.lightened(0.18)
	_quad(P(x1, d0, h0), P(x1, d1, h0), P(x1, d1, h1), P(x1, d0, h1), col.darkened(0.25))
	_quad(P(x0, d0, h1), P(x1, d0, h1), P(x1, d1, h1), P(x0, d1, h1), top)
	_quad(P(x0, d0, h0), P(x1, d0, h0), P(x1, d0, h1), P(x0, d0, h1), col)


func _quad(a: Vector2, b: Vector2, cc: Vector2, d: Vector2, col: Color) -> void:
	_fill(PackedVector2Array([a, b, cc, d]), col)


## An ellipse lying on the road (shadows, potholes, puddles, target rings).
func ground_ellipse(x: float, d: float, rx: float, rd: float, col: Color, h := 0.0, n := 16) -> void:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(P(x + cos(a) * rx, d + sin(a) * rd, h))
	_fill(out, col)


func ground_ring(x: float, d: float, rx: float, rd: float, col: Color, width: float) -> void:
	var out := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20
		out.append(P(x + cos(a) * rx, d + sin(a) * rd, 0.0))
	c.draw_polyline(out, col, width, true)


# ---------------------------------------------------------------- bikes

## A small commuter bike in profile, facing right, rear tyre contact at the
## pen origin. kind "70" is the red classic; "125" is black with red stripes;
## "warden" is white and blue. speed blurs the spokes.
func bike(kind: String, wheel_turn: float, t: float, helmet := true, speed := 0.0) -> void:
	var body := Color(0.84, 0.1, 0.1)
	var tank := body
	var stripe := Color(1, 1, 1)
	if kind == "125":
		body = Color(0.13, 0.13, 0.15)
		tank = Color(0.15, 0.15, 0.18)
		stripe = Color(0.92, 0.14, 0.12)
	elif kind == "warden":
		body = Color(0.95, 0.95, 0.97)
		tank = Color(0.12, 0.3, 0.7)
		stripe = Color(0.12, 0.3, 0.7)
	var big := 1.06 if kind == "125" else 1.0
	var rw := 0.31 * big
	var fx := 1.28 * big
	var black := Color(0.09, 0.09, 0.1)
	# Silencer and its heat shield: the pipe that goes PATAAKHA.
	limb(Vector2(0.8, 0.28), Vector2(0.24, 0.35), 0.065, CHROME.darkened(0.2))
	poly([Vector2(-0.32, 0.33), Vector2(0.28, 0.3), Vector2(0.3, 0.46), Vector2(-0.32, 0.49)], CHROME)
	poly([Vector2(-0.05, 0.43), Vector2(0.24, 0.42), Vector2(0.24, 0.48), Vector2(-0.05, 0.5)], Color(0.25, 0.25, 0.27))
	for i in 4:
		circle(0.0 + i * 0.065, 0.46, 0.012, Color(0.6, 0.6, 0.62))
	poly([Vector2(-0.4, 0.31), Vector2(-0.3, 0.33), Vector2(-0.3, 0.49), Vector2(-0.4, 0.51)], CHROME.darkened(0.35))
	ellipse(-0.4, 0.41, 0.015, 0.07, Color(0.05, 0.05, 0.05))
	# Wheels, sprockets and the chain under its black case.
	_wheel(0.0, rw, rw, wheel_turn, speed)
	_wheel(fx, rw, rw, wheel_turn, speed)
	circle(0.0, rw, rw * 0.42, Color(0.3, 0.3, 0.32))
	circle(0.62, 0.32, 0.075, Color(0.3, 0.3, 0.32))
	line(0.0, rw + rw * 0.42, 0.62, 0.395, 0.018, Color(0.2, 0.2, 0.2))
	line(0.0, rw - rw * 0.42, 0.62, 0.245, 0.018, Color(0.2, 0.2, 0.2))
	if kind != "125":
		poly([Vector2(-0.08, rw + 0.16), Vector2(0.62, 0.42), Vector2(0.7, 0.36), Vector2(0.62, 0.3), Vector2(0.05, rw + 0.04)], black)
	# Swingarm and rear shock.
	limb(Vector2(0.0, rw), Vector2(0.58, 0.42), 0.055, Color(0.18, 0.18, 0.2))
	line(0.05, rw + 0.05, 0.12, 0.68, 0.04, CHROME.darkened(0.1))
	for i in 5:
		line(0.06 + i * 0.012, rw + 0.12 + i * 0.07, 0.11 + i * 0.012, rw + 0.12 + i * 0.07, 0.015, Color(0.85, 0.2, 0.15) if kind != "warden" else Color(0.2, 0.3, 0.8))
	# Engine: cylinder with cooling fins, round crankcase cover, kick lever.
	poly([Vector2(0.5, 0.2), Vector2(0.92, 0.22), Vector2(0.98, 0.5), Vector2(0.56, 0.54)], Color(0.48, 0.48, 0.5))
	for i in 5:
		line(0.74, 0.3 + i * 0.05, 1.0, 0.32 + i * 0.05, 0.022, Color(0.62, 0.62, 0.64))
	circle(0.62, 0.32, 0.12, Color(0.72, 0.72, 0.75))
	circle(0.62, 0.32, 0.07, Color(0.55, 0.55, 0.58))
	line(0.5, 0.38, 0.3, 0.3, 0.025, Color(0.25, 0.25, 0.25))
	line(0.62, 0.3, 0.68, 0.12, 0.02, Color(0.3, 0.3, 0.3))       # footpeg stalk
	line(0.6, 0.12, 0.76, 0.12, 0.035, black)                    # footpeg
	# Frame tube under the tank.
	limb(Vector2(0.58, 0.55), Vector2(1.06 * big, 0.92), 0.06, body.darkened(0.25))
	# Rear mudguard, carrier, tail light and the number plate.
	poly([Vector2(-0.42, 0.42), Vector2(-0.02, 0.62), Vector2(0.24, 0.63), Vector2(-0.34, 0.35)], body)
	line(-0.18, 0.72, 0.3, 0.72, 0.03, CHROME)
	line(-0.18, 0.72, -0.08, 0.59, 0.025, CHROME)
	line(0.08, 0.72, 0.08, 0.63, 0.025, CHROME)
	ellipse(-0.4, 0.5, 0.05, 0.035, Color(1, 0.15, 0.1))
	circle(-0.41, 0.51, 0.015, Color(1, 0.8, 0.7))
	poly([Vector2(-0.48, 0.28), Vector2(-0.36, 0.3), Vector2(-0.36, 0.42), Vector2(-0.48, 0.4)], Color(0.97, 0.97, 0.92))
	# Side cover with the decal.
	poly([Vector2(0.26, 0.47), Vector2(0.62, 0.5), Vector2(0.6, 0.71), Vector2(0.22, 0.67)], body)
	text(0.43, 0.59, "125" if kind == "125" else ("70" if kind != "warden" else "W"), 0.13, stripe)
	# Seat with its stitching and shine.
	poly([Vector2(-0.02, 0.66), Vector2(0.64, 0.69), Vector2(0.68, 0.79), Vector2(0.4, 0.82), Vector2(0.04, 0.78)], Color(0.11, 0.1, 0.1))
	line(0.06, 0.74, 0.62, 0.76, 0.008, Color(0.35, 0.33, 0.3))
	line(0.12, 0.79, 0.5, 0.8, 0.015, Color(0.4, 0.4, 0.42, 0.6))
	# Tank with a white shine stroke and the fuel cap.
	poly([Vector2(0.6, 0.66), Vector2(0.84, 0.66), Vector2(1.04, 0.72), Vector2(1.03, 0.83), Vector2(0.86, 0.88), Vector2(0.66, 0.85)], tank)
	line(0.66, 0.76, 1.01, 0.78, 0.035, stripe)
	line(0.7, 0.84, 0.92, 0.85, 0.018, Color(1, 1, 1, 0.55))
	ellipse(0.82, 0.88, 0.04, 0.015, CHROME)
	# Front: fork, mudguard, headlight, speedo, bars, mirror, indicators.
	limb(Vector2(fx, rw), Vector2(1.08 * big, 1.0), 0.065, CHROME.darkened(0.1))
	line(fx - 0.02, rw + 0.12, fx - 0.07, rw + 0.38, 0.075, black)      # fork gaiter
	poly([Vector2(fx - 0.3, rw + 0.22), Vector2(fx - 0.05, rw + 0.34), Vector2(fx + 0.18, rw + 0.32), Vector2(fx + 0.34, rw + 0.12), Vector2(fx + 0.2, rw + 0.24)], body)
	circle(1.2 * big, 0.88, 0.11, CHROME)
	circle(1.23 * big, 0.88, 0.08, Color(1, 0.97, 0.78))
	circle(1.21 * big, 0.91, 0.03, Color(1, 1, 1))
	circle(1.08, 0.99, 0.06, black)
	circle(1.08, 0.99, 0.04, Color(0.85, 0.85, 0.8))
	line(1.0, 1.06, 1.14 * big, 1.0, 0.04, CHROME)
	line(0.96, 1.08, 1.04, 1.05, 0.05, black)                    # grip
	line(1.08, 1.02, 1.0, 1.3, 0.018, CHROME)
	ellipse(1.0, 1.33, 0.07, 0.05, CHROME)
	ellipse(1.01, 1.33, 0.05, 0.035, Color(0.55, 0.7, 0.85))
	line(1.12, 0.94, 1.2, 0.98, 0.02, black)
	ellipse(1.22, 0.99, 0.03, 0.02, Color(1, 0.6, 0.1))
	line(-0.3, 0.6, -0.4, 0.66, 0.02, black)
	ellipse(-0.42, 0.67, 0.03, 0.02, Color(1, 0.6, 0.1))
	if helmet:
		# The helmet rides on the mirror, never on the head. Classic.
		line(1.04, 1.18, 1.01, 1.06, 0.012, Color(0.2, 0.2, 0.2))
		poly([Vector2(0.88, 0.9), Vector2(1.14, 0.9), Vector2(1.13, 1.0), Vector2(1.07, 1.07), Vector2(0.96, 1.08), Vector2(0.89, 1.0)], Color(0.97, 0.84, 0.12))
		poly([Vector2(1.02, 0.92), Vector2(1.13, 0.92), Vector2(1.12, 0.99), Vector2(1.03, 0.99)], Color(0.15, 0.2, 0.3))
		line(0.92, 1.03, 1.0, 1.06, 0.015, Color(1, 1, 1, 0.6))


func _wheel(x: float, y: float, r: float, turn: float, speed := 0.0) -> void:
	circle(x, y, r, TYRE)
	# Tread blocks around the tyre, turning with it.
	for i in 18:
		var a := turn + i * TAU / 18.0
		var q := Vector2(cos(a), sin(a))
		line(x + q.x * r * 0.88, y + q.y * r * 0.88, x + q.x * r * 0.99, y + q.y * r * 0.99, 0.02, Color(0.2, 0.2, 0.22))
	circle(x, y, r * 0.8, Color(0.16, 0.16, 0.17))
	ring(x, y, r * 0.74, 0.03, CHROME)
	if speed > 9.0:
		# Spokes too fast to see: a soft disc with a hint of streaks.
		circle(x, y, r * 0.7, Color(0.62, 0.63, 0.66, 0.35))
		for i in 3:
			var a := turn * 0.2 + i * TAU / 3.0
			line(x, y, x + cos(a) * r * 0.68, y + sin(a) * r * 0.68, 0.01, Color(1, 1, 1, 0.25))
	else:
		for i in 16:
			var a := turn + i * PI / 8.0
			line(x + cos(a) * r * 0.12, y + sin(a) * r * 0.12, x + cos(a + 0.35) * r * 0.72, y + sin(a + 0.35) * r * 0.72, 0.008, CHROME)
	circle(x, y, r * 0.2, Color(0.5, 0.5, 0.52))
	circle(x, y, r * 0.09, CHROME)


# ---------------------------------------------------------------- Shani

## Joint positions per pose, in the bike's frame (rear contact at 0,0).
const POSES := {
	"ride": {"hip": Vector2(0.36, 0.86), "knee": Vector2(0.76, 0.84), "foot": Vector2(0.62, 0.42),
		"shoulder": Vector2(0.58, 1.42), "elbow": Vector2(0.84, 1.22), "hand": Vector2(1.03, 1.06),
		"far_elbow": Vector2(0.8, 1.22), "far_hand": Vector2(1.0, 1.06), "head": Vector2(0.66, 1.63)},
	"no_hands": {"hip": Vector2(0.36, 0.86), "knee": Vector2(0.76, 0.84), "foot": Vector2(0.62, 0.42),
		"shoulder": Vector2(0.5, 1.45), "elbow": Vector2(0.66, 1.76), "hand": Vector2(0.78, 2.05),
		"far_elbow": Vector2(0.36, 1.78), "far_hand": Vector2(0.3, 2.06), "head": Vector2(0.55, 1.7)},
	"superman": {"hip": Vector2(0.1, 1.42), "knee": Vector2(-0.38, 1.6), "foot": Vector2(-0.86, 1.72),
		"shoulder": Vector2(0.74, 1.3), "elbow": Vector2(0.9, 1.18), "hand": Vector2(1.03, 1.06),
		"far_elbow": Vector2(0.88, 1.2), "far_hand": Vector2(1.0, 1.06), "head": Vector2(0.93, 1.46)},
	"seat_stand": {"hip": Vector2(0.34, 1.62), "knee": Vector2(0.46, 1.2), "foot": Vector2(0.34, 0.8),
		"shoulder": Vector2(0.38, 2.22), "elbow": Vector2(0.74, 2.42), "hand": Vector2(1.06, 2.58),
		"far_elbow": Vector2(0.04, 2.42), "far_hand": Vector2(-0.28, 2.58), "head": Vector2(0.42, 2.45)},
	"selfie": {"hip": Vector2(0.36, 0.86), "knee": Vector2(0.76, 0.84), "foot": Vector2(0.62, 0.42),
		"shoulder": Vector2(0.56, 1.42), "elbow": Vector2(0.88, 1.58), "hand": Vector2(1.22, 1.86),
		"far_elbow": Vector2(0.8, 1.22), "far_hand": Vector2(1.0, 1.06), "head": Vector2(0.62, 1.64)},
}


## Shani on the bike, in the bike's pen frame. Far limbs first (darker),
## then the bike is drawn by the caller, then call shani_front().
func shani_back(pose: String) -> void:
	var j: Dictionary = POSES.get(pose, POSES.ride)
	limb(j.hip, j.knee, 0.2, KAMEEZ_DARK.lightened(0.1))
	limb(j.knee, j.foot + Vector2(0.06, 0.02), 0.16, KAMEEZ_DARK.lightened(0.1))
	limb(j.shoulder, j.far_elbow, 0.12, KAMEEZ_DARK)
	var fh: Vector2 = j.far_hand
	limb(j.far_elbow, (j.far_elbow as Vector2).lerp(fh, 0.82), 0.1, KAMEEZ_DARK)
	circle(fh.x, fh.y, 0.05, SKIN_DARK)


func shani_front(pose: String, t: float, speed: float, mood := "") -> void:
	var j: Dictionary = POSES.get(pose, POSES.ride)
	var hip: Vector2 = j.hip
	var sh: Vector2 = j.shoulder
	var light := KAMEEZ.lightened(0.12)
	# The kameez tail flaps in the wind: faster riding, faster flapping.
	var flap := sin(t * (8.0 + speed * 1.2)) * 0.05 * minf(1.0, speed / 8.0)
	var flap2 := sin(t * (8.0 + speed * 1.2) + 1.3) * 0.04 * minf(1.0, speed / 8.0)
	var back := (hip - sh).normalized()
	var side := Vector2(back.y, -back.x)   # perpendicular, towards the rear
	var tail := hip + back * 0.3 + side * (0.24 + speed * 0.012) + Vector2(0, flap)
	var tail2 := hip + back * 0.18 + side * (0.3 + speed * 0.014) + Vector2(0, flap2)
	poly([sh + side * -0.16, sh + side * 0.17, hip + side * 0.2, tail2, tail, hip + back * 0.32 - side * 0.12, hip - side * 0.16], KAMEEZ)
	# Folds in the cloth, the placket and its buttons, the collar.
	var save_ink := ink
	ink = 0.0
	line(hip.x + side.x * 0.1, hip.y + side.y * 0.1, tail.x - side.x * 0.05, tail.y - 0.02, 0.012, KAMEEZ_DARK)
	line(sh.x + side.x * 0.08, sh.y - 0.05, hip.x + side.x * 0.14, hip.y + 0.02, 0.01, KAMEEZ_DARK)
	line(sh.x - side.x * 0.05, sh.y - 0.02, sh.x - side.x * 0.05 + back.x * 0.32, sh.y - 0.02 + back.y * 0.32, 0.014, KAMEEZ_DARK)
	for i in 3:
		var bpos := sh - side * 0.06 + back * (0.06 + i * 0.09)
		circle(bpos.x, bpos.y, 0.013, Color(0.95, 0.95, 0.95))
	poly([sh + side * -0.14 + Vector2(0, 0.02), sh + side * 0.06 + Vector2(0, 0.06), sh + side * 0.02 + Vector2(0, -0.03)], light)
	ink = save_ink
	# Near leg: baggy shalwar gathered at the ankle, and a chappal.
	var knee: Vector2 = j.knee
	var foot: Vector2 = j.foot
	limb(hip, knee, 0.22, light)
	var shin := (foot - knee).normalized()
	var shin_n := Vector2(shin.y, -shin.x)
	poly([knee + shin_n * 0.12, knee - shin_n * 0.12, foot - shin_n * 0.06 + shin * -0.04, foot + shin_n * 0.06 + shin * -0.04], light)
	poly([foot + Vector2(-0.08, -0.05), foot + Vector2(0.17, -0.05), foot + Vector2(0.15, 0.02), foot + Vector2(-0.06, 0.04)], Color(0.45, 0.25, 0.12))
	line(foot.x + 0.02, foot.y + 0.01, foot.x + 0.1, foot.y - 0.03, 0.025, Color(0.3, 0.15, 0.06))
	# Head: neck, ear, gelled-up hair, shades, eyebrow, nose, moustache.
	var hd: Vector2 = j.head
	limb(sh + Vector2(0.02, 0.02), hd + Vector2(-0.01, -0.09), 0.09, SKIN_DARK)
	circle(hd.x, hd.y, 0.14, SKIN)
	poly([hd + Vector2(0.11, 0.02), hd + Vector2(0.19, -0.02), hd + Vector2(0.12, -0.05)], SKIN)   # nose
	circle(hd.x - 0.06, hd.y + 0.0, 0.035, SKIN_DARK)                                              # ear
	poly([hd + Vector2(-0.15, 0.0), hd + Vector2(-0.13, 0.14), hd + Vector2(-0.05, 0.26), hd + Vector2(-0.01, 0.17),
		hd + Vector2(0.05, 0.29), hd + Vector2(0.09, 0.17), hd + Vector2(0.17, 0.23), hd + Vector2(0.15, 0.07),
		hd + Vector2(0.03, 0.1), hd + Vector2(-0.08, 0.05)], HAIR)
	ink = 0.0
	line(hd.x - 0.04, hd.y + 0.16, hd.x + 0.04, hd.y + 0.22, 0.02, Color(0.35, 0.35, 0.4, 0.8))    # gel shine
	poly([hd + Vector2(0.0, 0.0), hd + Vector2(0.17, 0.01), hd + Vector2(0.16, 0.065), hd + Vector2(0.04, 0.06)], Color(0.04, 0.04, 0.07))
	line(hd.x + 0.06, hd.y + 0.045, hd.x + 0.13, hd.y + 0.025, 0.012, Color(0.7, 0.85, 1, 0.9))    # lens glint
	line(hd.x - 0.05, hd.y + 0.04, hd.x + 0.01, hd.y + 0.03, 0.018, Color(0.04, 0.04, 0.07))
	line(hd.x + 0.04, hd.y + 0.09, hd.x + 0.15, hd.y + 0.085, 0.022, HAIR)                        # eyebrow
	ink = save_ink
	if mood == "yell":
		ellipse(hd.x + 0.11, hd.y - 0.085, 0.045, 0.04, Color(0.35, 0.05, 0.05))
		ellipse(hd.x + 0.115, hd.y - 0.1, 0.025, 0.012, Color(0.9, 0.4, 0.4))
	else:
		line(hd.x + 0.08, hd.y - 0.065, hd.x + 0.15, hd.y - 0.055, 0.016, Color(0.4, 0.15, 0.1))
	line(hd.x + 0.07, hd.y - 0.035, hd.x + 0.16, hd.y - 0.03, 0.022, Color(0.12, 0.08, 0.06))      # moustache
	# Near arm: kameez sleeve to the wrist, then the hand.
	var hand: Vector2 = j.hand
	var el: Vector2 = j.elbow
	limb(sh, el, 0.13, KAMEEZ)
	var wrist := el.lerp(hand, 0.82)
	limb(el, wrist, 0.11, KAMEEZ)
	circle(hand.x, hand.y, 0.055, SKIN)
	if pose == "selfie":
		poly([hand + Vector2(-0.03, -0.02), hand + Vector2(0.06, 0.05), hand + Vector2(0.02, 0.18), hand + Vector2(-0.07, 0.11)], Color(0.1, 0.1, 0.12))
		if fmod(t, 0.5) < 0.12:
			circle(hand.x + 0.0, hand.y + 0.08, 0.16, Color(1, 1, 1, 0.8))


## Shani off the bike: flying, then flat on the road, then up again.
## `phase` 0..1 through the crash. `spin` is the tumble angle.
func shani_tumble(phase: float, spin: float, t: float) -> void:
	var down := phase > 0.4 and phase < 0.8
	if phase >= 0.8:
		# Back on his feet, dusting off.
		rot = 0.0
		var wob := sin(t * 10.0) * 0.04
		limb(Vector2(-0.1, 0.0), Vector2(-0.05, 0.85), 0.18, KAMEEZ.lightened(0.12))
		limb(Vector2(0.12, 0.0), Vector2(0.05, 0.85), 0.18, KAMEEZ.lightened(0.12))
		poly([Vector2(-0.2, 0.5), Vector2(0.2, 0.5), Vector2(0.18, 1.45), Vector2(-0.18, 1.45)], KAMEEZ)
		limb(Vector2(0.15, 1.38), Vector2(0.4, 1.0 + wob), 0.1, SKIN)
		limb(Vector2(-0.15, 1.38), Vector2(-0.38, 1.0 - wob), 0.1, SKIN)
		circle(0.0, 1.62, 0.14, SKIN)
		poly([Vector2(-0.14, 1.64), Vector2(-0.1, 1.82), Vector2(0.0, 1.74), Vector2(0.08, 1.85), Vector2(0.14, 1.66)], HAIR)
		rect(-0.08, 1.6, 0.1, 1.65, Color(0.05, 0.05, 0.08))
		return
	if down:
		rot = -PI / 2.0 + 0.1
	else:
		rot = spin
	# A star-shape sprawl: arms and legs everywhere.
	limb(Vector2(0, 0.7), Vector2(-0.45, 0.1), 0.18, KAMEEZ.lightened(0.12))
	limb(Vector2(0, 0.7), Vector2(0.4, 0.05), 0.18, KAMEEZ.lightened(0.12))
	poly([Vector2(-0.2, 0.55), Vector2(0.2, 0.55), Vector2(0.22, 1.35), Vector2(-0.22, 1.35)], KAMEEZ)
	limb(Vector2(0.18, 1.3), Vector2(0.62, 1.62), 0.1, SKIN)
	limb(Vector2(-0.18, 1.3), Vector2(-0.6, 1.6), 0.1, SKIN)
	circle(0.0, 1.58, 0.14, SKIN)
	poly([Vector2(-0.14, 1.6), Vector2(-0.1, 1.78), Vector2(0.0, 1.7), Vector2(0.08, 1.8), Vector2(0.14, 1.62)], HAIR)
	if down:
		# Cartoon dizzy stars.
		for i in 3:
			var a := t * 4.0 + i * TAU / 3.0
			_star(cos(a) * 0.3, 1.95 + sin(a) * 0.08, 0.07, Color(1, 0.9, 0.2))


func _star(x: float, y: float, r: float, col: Color) -> void:
	var pts: Array = []
	for i in 10:
		var a := PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(Vector2(x + cos(a) * rr, y + sin(a) * rr))
	poly(pts, col)


# ---------------------------------------------------------------- people

## A person seen from the front or back (crossing the road), or standing on
## the footpath. look picks clothes and type. `walk` animates the legs.
func person(look: int, walk: float, scared := false, cheer := false, facing := 1.0) -> void:
	var cloth: Color = [Color(0.95, 0.95, 0.92), Color(0.55, 0.75, 0.9), Color(0.75, 0.6, 0.45),
		Color(0.45, 0.5, 0.45), Color(0.9, 0.55, 0.6), Color(0.35, 0.4, 0.6), Color(0.85, 0.8, 0.55),
		Color(0.6, 0.3, 0.3)][look % 8]
	var kind := look % 5          # 0,1 uncle  2 aunty  3 kid  4 old man
	var k := 0.72 if kind == 3 else 1.0
	var skin := SKIN if look % 3 != 0 else SKIN_DARK
	var step := sin(walk) * 0.12
	var lift := 0.25 if scared else 0.0
	# Legs.
	limb(Vector2(-0.09, (0.8 + lift) * k), Vector2(-0.1 + step, lift * k), 0.13 * k, cloth.darkened(0.15))
	limb(Vector2(0.09, (0.8 + lift) * k), Vector2(0.1 - step, lift * k), 0.13 * k, cloth.darkened(0.15))
	# Kameez (long), and for uncles a waistcoat.
	poly([Vector2(-0.22 * k, (0.45 + lift) * k), Vector2(0.22 * k, (0.45 + lift) * k), Vector2(0.2 * k, (1.42 + lift) * k), Vector2(-0.2 * k, (1.42 + lift) * k)], cloth)
	if kind <= 1:
		poly([Vector2(-0.2, 0.95 + lift), Vector2(-0.04, 0.95 + lift), Vector2(-0.06, 1.42 + lift), Vector2(-0.19, 1.42 + lift)], Color(0.25, 0.22, 0.2))
		poly([Vector2(0.04, 0.95 + lift), Vector2(0.2, 0.95 + lift), Vector2(0.19, 1.42 + lift), Vector2(0.06, 1.42 + lift)], Color(0.25, 0.22, 0.2))
	# Arms.
	var up := scared or cheer
	var wave := sin(walk * 2.0) * 0.1 if cheer else 0.0
	if up:
		limb(Vector2(-0.2 * k, 1.35 * k + lift), Vector2(-0.42 * k, (1.95 + wave) * k + lift), 0.09 * k, skin)
		limb(Vector2(0.2 * k, 1.35 * k + lift), Vector2(0.42 * k, (1.95 - wave) * k + lift), 0.09 * k, skin)
	else:
		limb(Vector2(-0.21 * k, 1.35 * k), Vector2(-0.28 * k - step * 0.3, 0.8 * k), 0.09 * k, cloth.darkened(0.05))
		limb(Vector2(0.21 * k, 1.35 * k), Vector2(0.28 * k + step * 0.3, 0.8 * k), 0.09 * k, cloth.darkened(0.05))
	# Head.
	var hy := (1.6 + lift) * k
	circle(0.0, hy, 0.14 * k, skin)
	match kind:
		0, 1:
			poly([Vector2(-0.14, hy + 0.02), Vector2(0.14, hy + 0.02), Vector2(0.12, hy + 0.13), Vector2(-0.12, hy + 0.13)], Color(0.15, 0.12, 0.1))
			line(-0.07 * facing, hy - 0.05, 0.07 * facing, hy - 0.05, 0.03, Color(0.15, 0.12, 0.1))   # moustache
			if kind == 1:
				ring(-0.05, hy, 0.04, 0.012, Color(0.1, 0.1, 0.1))
				ring(0.05, hy, 0.04, 0.012, Color(0.1, 0.1, 0.1))
		2:
			# Dupatta over the head and shoulders, and the shopping bag.
			var dup := Color(0.95, 0.5, 0.2) if look % 2 == 0 else Color(0.3, 0.65, 0.4)
			poly([Vector2(-0.19, hy - 0.12), Vector2(-0.16, hy + 0.12), Vector2(0.0, hy + 0.19), Vector2(0.16, hy + 0.12), Vector2(0.19, hy - 0.12), Vector2(0.25, 1.15), Vector2(-0.25, 1.15)], dup)
			circle(0.0, hy - 0.01, 0.11, skin)
			if not up:
				rect(0.26, 0.55, 0.48, 0.85, Color(0.95, 0.95, 0.9))
				line(0.3, 0.85, 0.28, 1.0, 0.02, Color(0.6, 0.6, 0.6))
		3:
			poly([Vector2(-0.11, hy + 0.04), Vector2(0.11, hy + 0.04), Vector2(0.08, hy + 0.12), Vector2(-0.08, hy + 0.12)], HAIR)
			rect(-0.18, 0.7, 0.18, 1.0, Color(0.2, 0.35, 0.75))    # school bag
		4:
			poly([Vector2(-0.12, hy + 0.06), Vector2(0.12, hy + 0.06), Vector2(0.1, hy + 0.12), Vector2(-0.1, hy + 0.12)], Color(0.9, 0.9, 0.9))
			line(0.32, 0.0, 0.3, 1.0, 0.03, Color(0.45, 0.3, 0.15))    # walking stick
	if scared or cheer:
		ellipse(0.0, hy - 0.07 * k, 0.04 * k, 0.045 * k, Color(0.3, 0.05, 0.05))


## A goat in profile, facing +x (use flip for -x).
func goat(look: int, walk: float) -> void:
	var col: Color = [Color(0.95, 0.94, 0.9), Color(0.2, 0.18, 0.16), Color(0.6, 0.42, 0.25)][look % 3]
	var step := sin(walk) * 0.08
	for lx in [-0.28, -0.18, 0.22, 0.32]:
		var sgn := 1.0 if lx < 0.0 else -1.0
		line(lx, 0.45, lx + step * sgn, 0.0, 0.05, col.darkened(0.3))
	ellipse(0.0, 0.55, 0.42, 0.2, col)
	poly([Vector2(0.3, 0.6), Vector2(0.45, 0.85), Vector2(0.6, 0.82), Vector2(0.48, 0.55)], col)
	ellipse(0.58, 0.8, 0.12, 0.08, col)
	line(0.52, 0.88, 0.45, 1.0, 0.03, Color(0.5, 0.45, 0.4))       # horn
	line(0.5, 0.78, 0.4, 0.68, 0.04, col.darkened(0.2))           # ear
	circle(0.62, 0.83, 0.018, Color(0.1, 0.1, 0.1))
	line(-0.42, 0.6, -0.5, 0.72, 0.04, col)                        # tail


## A pigeon. flying: 0 = pecking on the road, >0 = time since take-off.
func pigeon(look: int, t: float, flying: float) -> void:
	var col := Color(0.55, 0.57, 0.62) if look % 3 != 0 else Color(0.42, 0.4, 0.42)
	if flying <= 0.0:
		var peck := 0.05 if fmod(t * 2.0 + look * 0.37, 1.0) < 0.2 else 0.0
		ellipse(0.0, 0.12, 0.14, 0.08, col)
		circle(0.13, 0.2 - peck * 2.0, 0.05, col.darkened(0.1))
		circle(0.15, 0.21 - peck * 2.0, 0.012, Color(0.9, 0.4, 0.1))
		line(0.0, 0.05, 0.0, 0.0, 0.015, Color(0.8, 0.4, 0.4))
		return
	var flap := sin(t * 26.0 + look)
	var save_ink := ink
	ink = minf(ink, 1.0)
	# Far wing, body with a tail fan, head, near wing: a flap is the wings
	# swinging from above the body to below it.
	poly([Vector2(-0.06, 0.02), Vector2(0.06, 0.03), Vector2(0.02, 0.05 + 0.2 * flap), Vector2(-0.14, 0.04 + 0.16 * flap)], col.darkened(0.2))
	poly([Vector2(-0.2, -0.02), Vector2(-0.3, -0.05), Vector2(-0.3, 0.05), Vector2(-0.2, 0.03)], col.darkened(0.15))
	ellipse(0.0, 0.0, 0.15, 0.065, col)
	circle(0.15, 0.035, 0.05, col.darkened(0.05))
	poly([Vector2(0.19, 0.03), Vector2(0.24, 0.02), Vector2(0.19, 0.015)], Color(0.85, 0.6, 0.4))
	poly([Vector2(-0.05, 0.0), Vector2(0.07, 0.01), Vector2(0.0, 0.02 + 0.24 * flap), Vector2(-0.17, 0.0 + 0.2 * flap)], col.lightened(0.12))
	ink = save_ink


# ---------------------------------------------------------------- vehicles

## Auto-rickshaw. The pen is at (x, d0) on the road, facing `dir`.
func rickshaw(x: float, d: float, dir: float, look: int, t: float) -> void:
	var body: Color = [Color(0.15, 0.55, 0.3), Color(0.95, 0.75, 0.1), Color(0.2, 0.4, 0.75)][look % 3]
	var d0 := d - 0.7
	var d1 := d + 0.7
	var bounce := sin(t * 14.0 + look) * 0.02
	box(x - 1.3, x + 1.3, d0 + 0.05, d1 - 0.05, 0.25 + bounce, 0.95 + bounce, body)
	# Canopy: black canvas roof on thin posts, open sides.
	box(x - 1.25, x + 0.85 * dir, d0, d1, 1.62 + bounce, 1.78 + bounce, Color(0.1, 0.1, 0.1))
	pen(P(x, d0, 0.0), s, 0.0, dir)
	line(-1.2, 0.95 + bounce, -1.2, 1.62 + bounce, 0.05, Color(0.1, 0.1, 0.1))
	line(0.82, 0.95 + bounce, 0.82, 1.62 + bounce, 0.05, Color(0.1, 0.1, 0.1))
	# The driver up front and a passenger in the back.
	circle(0.45, 1.36 + bounce, 0.13, SKIN)
	poly([Vector2(0.3, 0.95), Vector2(0.62, 0.95), Vector2(0.58, 1.24), Vector2(0.34, 1.24)], Color(0.85, 0.85, 0.82))
	circle(-0.55, 1.34 + bounce, 0.13, SKIN_DARK)
	poly([Vector2(-0.72, 0.95), Vector2(-0.38, 0.95), Vector2(-0.42, 1.22), Vector2(-0.68, 1.22)], Color(0.6, 0.3, 0.35))
	# The nose and decorations: tassels along the roof and a big painted eye.
	poly([Vector2(1.3, 0.25 + bounce), Vector2(1.45, 0.4 + bounce), Vector2(1.38, 1.0 + bounce), Vector2(1.3, 0.95 + bounce)], body.darkened(0.15))
	for i in 9:
		var tx := -1.2 + i * 0.25
		poly([Vector2(tx, 1.62 + bounce), Vector2(tx + 0.12, 1.62 + bounce), Vector2(tx + 0.06, 1.5 + bounce)],
			[Color(1, 0.2, 0.3), Color(1, 0.85, 0.1), Color(0.2, 0.8, 0.4)][i % 3])
	ellipse(-0.1, 0.6 + bounce, 0.18, 0.1, Color(1, 1, 1))
	circle(-0.1, 0.6 + bounce, 0.06, Color(0.1, 0.3, 0.8))
	_wheel(-0.85, 0.25, 0.25, -x * dir / 0.25)
	_wheel(1.05, 0.25, 0.25, -x * dir / 0.25)


## The white passenger wagon, with a conductor hanging out of the door.
func wagon(x: float, d: float, look: int, t: float) -> void:
	var body := Color(0.94, 0.94, 0.92) if look % 2 == 0 else Color(0.85, 0.9, 0.95)
	var d0 := d - 0.9
	var bounce := sin(t * 11.0 + look) * 0.02
	box(x - 2.2, x + 2.2, d0, d + 0.9, 0.3 + bounce, 2.0 + bounce, body)
	# Luggage on the roof.
	box(x - 1.6, x - 0.2, d0 + 0.3, d + 0.6, 2.0 + bounce, 2.4 + bounce, Color(0.55, 0.35, 0.2))
	box(x - 0.1, x + 1.0, d0 + 0.4, d + 0.5, 2.0 + bounce, 2.28 + bounce, Color(0.25, 0.45, 0.7))
	pen(P(x, d0, 0.0), s)
	rect(-2.0, 1.15 + bounce, 1.6, 1.7 + bounce, Color(0.25, 0.4, 0.5))
	for i in 5:
		circle(-1.7 + i * 0.65, 1.38 + bounce, 0.12, [SKIN, SKIN_DARK][i % 2])
	rect(-2.2, 0.75 + bounce, 2.2, 0.85 + bounce, Color(0.85, 0.15, 0.15))
	text(0.0, 0.52 + bounce, "SADDAR - RAJA BAZAAR", 0.2, Color(0.15, 0.15, 0.6))
	rect(1.7, 1.15 + bounce, 2.15, 1.7 + bounce, Color(0.3, 0.45, 0.55))
	# The conductor: one foot on the step, one hand on the rail, shouting.
	limb(Vector2(0.4, 0.4), Vector2(0.55, 1.1), 0.12, Color(0.6, 0.5, 0.35))
	poly([Vector2(0.4, 1.0), Vector2(0.75, 1.0), Vector2(0.75, 1.6), Vector2(0.45, 1.6)], Color(0.6, 0.5, 0.35))
	limb(Vector2(0.7, 1.5), Vector2(1.05, 1.7 + sin(t * 6.0) * 0.1), 0.08, SKIN)
	circle(0.62, 1.78, 0.13, SKIN)
	_wheel(-1.5, 0.3, 0.3, -x / 0.3)
	_wheel(1.5, 0.3, 0.3, -x / 0.3)


## A truck-art bus: every panel painted, chains, a man on the roof.
func bus(x: float, d: float, look: int, t: float) -> void:
	var d0 := d - 1.2
	var bounce := sin(t * 8.0 + look) * 0.025
	var base := Color(0.98, 0.78, 0.1) if look % 2 == 0 else Color(0.95, 0.35, 0.15)
	box(x - 5.25, x + 5.25, d0, d + 1.2, 0.4 + bounce, 3.3 + bounce, base)
	box(x - 4.5, x + 3.0, d0 + 0.3, d + 0.9, 3.3 + bounce, 3.65 + bounce, Color(0.5, 0.32, 0.18))
	pen(P(x, d0, 0.0), s)
	# Painted bands.
	rect(-5.25, 0.4 + bounce, 5.25, 0.85 + bounce, Color(0.1, 0.45, 0.8))
	rect(-5.25, 1.55 + bounce, 5.25, 1.75 + bounce, Color(0.85, 0.1, 0.25))
	for i in 14:
		var fx := -4.9 + i * 0.75
		_flower(fx, 0.62 + bounce, 0.15, [Color(1, 0.3, 0.5), Color(1, 1, 1), Color(0.3, 0.9, 0.4)][i % 3])
	# Windows with passengers.
	for i in 8:
		var wx := -4.6 + i * 1.12
		rect(wx, 1.9 + bounce, wx + 0.85, 2.85 + bounce, Color(0.22, 0.35, 0.42))
		circle(wx + 0.42, 2.25 + bounce, 0.15, [SKIN, SKIN_DARK][(i + look) % 2])
	text(0.0, 3.05 + bounce, "PINDI EXPRESS", 0.28, Color(0.75, 0.05, 0.1))
	# Chains dangling from the bumper.
	for i in 12:
		var cx := -5.0 + i * 0.9
		var swing := sin(t * 9.0 + i) * 0.05
		line(cx, 0.4 + bounce, cx + swing, 0.15 + bounce, 0.02, CHROME)
	# The man on the roof.
	circle(2.0, 4.0 + bounce, 0.14, SKIN)
	poly([Vector2(1.8, 3.65), Vector2(2.2, 3.65), Vector2(2.15, 3.9), Vector2(1.85, 3.9)], Color(0.9, 0.9, 0.85))
	_wheel(-3.6, 0.45, 0.45, -x / 0.45)
	_wheel(3.6, 0.45, 0.45, -x / 0.45)


func _flower(x: float, y: float, r: float, col: Color) -> void:
	for i in 5:
		var a := i * TAU / 5.0
		circle(x + cos(a) * r * 0.55, y + sin(a) * r * 0.55, r * 0.45, col)
	circle(x, y, r * 0.35, Color(1, 0.85, 0.1))


## A thela (hand cart): fruit, or trays of eggs; the vendor pushes it.
func cart(x: float, d: float, eggs: bool, look: int, t: float) -> void:
	var d0 := d - 0.65
	box(x - 1.1, x + 1.1, d0, d + 0.65, 0.6, 0.85, Color(0.6, 0.4, 0.2))
	pen(P(x, d0, 0.0), s)
	_wheel(0.0, 0.35, 0.35, -x / 0.35)
	line(-1.1, 0.75, -1.6, 0.95, 0.04, Color(0.45, 0.3, 0.15))
	if eggs:
		# The anday wala burger thela: a glass case of buns, a hot tawa with
		# eggs frying, ketchup and chutney bottles, the gas cylinder below.
		box(x - 1.1, x + 0.2, d0 + 0.1, d + 0.55, 0.85, 1.35, Color(0.75, 0.85, 0.9, 0.55))
		pen(P(x, d0 + 0.1, 0.0), s)
		for i in 3:
			for j in 2:
				ellipse(-0.9 + i * 0.35, 0.95 + j * 0.18, 0.15, 0.07, Color(0.92, 0.68, 0.3))
		pen(P(x, d0, 0.0), s)
		rect(0.2, 0.85, 1.05, 0.92, Color(0.15, 0.15, 0.15))            # the tawa
		for i in 3:
			var ex := 0.35 + i * 0.25
			ellipse(ex, 0.93, 0.11, 0.035, Color(0.98, 0.97, 0.92))
			circle(ex, 0.94, 0.035, Color(1, 0.75, 0.1))
		for i in 2:
			var steam := fmod(t * 0.8 + i * 0.5, 1.0)
			circle(0.45 + i * 0.3, 1.05 + steam * 0.5, 0.06 + steam * 0.05, Color(1, 1, 1, 0.35 * (1.0 - steam)))
		rect(0.95, 0.92, 1.03, 1.15, Color(0.85, 0.1, 0.1))               # ketchup
		rect(0.85, 0.92, 0.92, 1.12, Color(0.2, 0.6, 0.25))               # chutney
		ellipse(-0.3, 0.32, 0.18, 0.25, Color(0.2, 0.35, 0.75))           # gas cylinder
		rect(-1.05, 1.55, 1.05, 1.85, Color(0.95, 0.85, 0.15))
		text(0.0, 1.69, "ANDA SHAMI BURGER", 0.17, Color(0.75, 0.05, 0.05))
		line(-1.0, 0.85, -1.0, 1.55, 0.03, Color(0.4, 0.3, 0.2))
		line(1.0, 0.85, 1.0, 1.55, 0.03, Color(0.4, 0.3, 0.2))
	else:
		var fruit: Color = [Color(1, 0.55, 0.05), Color(0.95, 0.85, 0.15), Color(0.85, 0.1, 0.15)][look % 3]
		for row in 3:
			for i in 7 - row * 2:
				var fx := -0.75 + row * 0.25 + i * 0.25
				var top := P(x + fx, d - 0.1, 0.95 + row * 0.18)
				c.draw_circle(top, 0.13 * s, fruit)
				c.draw_circle(top + Vector2(-0.04, -0.04) * s, 0.04 * s, fruit.lightened(0.4))
	# The vendor, walking behind.
	pen(P(x - 1.85, d0 + 0.2, 0.0), s)
	var step := sin(t * 5.0) * 0.1
	limb(Vector2(0.0, 0.85), Vector2(step, 0.0), 0.14, Color(0.85, 0.85, 0.8))
	limb(Vector2(0.0, 0.85), Vector2(-step, 0.0), 0.14, Color(0.75, 0.75, 0.7))
	poly([Vector2(-0.2, 0.6), Vector2(0.2, 0.6), Vector2(0.24, 1.45), Vector2(-0.16, 1.45)], Color(0.85, 0.85, 0.8))
	limb(Vector2(0.15, 1.35), Vector2(0.3, 0.97), 0.09, SKIN_DARK)
	circle(0.08, 1.62, 0.14, SKIN_DARK)
	rect(-0.06, 1.7, 0.2, 1.78, Color(0.95, 0.95, 0.95))


## The baraat: the dulha on a white horse, a dhol player, dancers and a man
## carrying the lights on his head. Spread over two lanes.
func baraat(x: float, d: float, look: int, t: float) -> void:
	var beat := absf(sin(t * 7.0))
	# Lights on a pole, far side.
	pen(P(x + 3.2, d + 1.8, 0.0), s)
	person(look + 3, t * 5.0, false, false)
	line(0.0, 1.8, 0.0, 2.9, 0.04, Color(0.4, 0.4, 0.4))
	for i in 5:
		circle(-0.4 + i * 0.2, 2.9 + (0.05 if (i + int(t * 6.0)) % 2 == 0 else 0.0), 0.07,
			[Color(1, 0.3, 0.3), Color(1, 1, 0.4), Color(0.4, 1, 0.5), Color(0.4, 0.7, 1), Color(1, 0.5, 1)][i])
	# Dancers.
	for i in 3:
		pen(P(x - 2.5 + i * 1.3, d + 0.9 - i * 0.6, beat * 0.15), s)
		person(look + i, t * 9.0 + i, false, true)
	# Dhol player.
	pen(P(x + 1.0, d - 1.2, 0.0), s)
	person(look + 7, t * 6.0)
	ellipse(0.0, 1.0, 0.32, 0.22, Color(0.75, 0.2, 0.15))
	line(-0.3, 1.0 + beat * 0.2, -0.5, 1.3 + beat * 0.2, 0.03, Color(0.4, 0.25, 0.1))
	# The horse and the dulha.
	pen(P(x - 1.0, d - 1.6, 0.0), s)
	var hstep := sin(t * 4.0) * 0.08
	for lx in [-0.55, -0.4, 0.45, 0.6]:
		line(lx, 1.0, lx + hstep * (1.0 if lx < 0 else -1.0), 0.0, 0.08, Color(0.92, 0.92, 0.9))
	ellipse(0.0, 1.15, 0.75, 0.32, Color(0.95, 0.95, 0.93))
	poly([Vector2(0.55, 1.2), Vector2(0.85, 1.75), Vector2(1.05, 1.7), Vector2(0.75, 1.1)], Color(0.95, 0.95, 0.93))
	ellipse(1.02, 1.68, 0.2, 0.12, Color(0.95, 0.95, 0.93))
	rect(-0.5, 1.05, 0.45, 1.42, Color(0.8, 0.1, 0.2))                 # decorated cloth
	for i in 6:
		circle(-0.45 + i * 0.18, 1.05, 0.04, Color(1, 0.85, 0.2))
	# Dulha: cream sherwani, gold turban, flower sehra over his face.
	poly([Vector2(-0.15, 1.45), Vector2(0.2, 1.45), Vector2(0.15, 2.2), Vector2(-0.1, 2.2)], Color(0.98, 0.92, 0.75))
	circle(0.03, 2.38, 0.14, SKIN)
	poly([Vector2(-0.15, 2.4), Vector2(0.2, 2.4), Vector2(0.16, 2.6), Vector2(0.03, 2.72), Vector2(-0.12, 2.6)], Color(1, 0.75, 0.15))
	for i in 5:
		line(-0.1 + i * 0.06, 2.42, -0.1 + i * 0.06, 2.18, 0.02, Color(1, 1, 1))


## The traffic warden on his bike. hat_off: his cap is flying away.
func warden_rider(t: float, hat_off: float) -> void:
	var uni := Color(0.15, 0.22, 0.45)
	var j: Dictionary = POSES.ride
	limb(j.hip, j.knee, 0.17, Color(0.1, 0.1, 0.15))
	limb(j.knee, j.foot, 0.15, Color(0.1, 0.1, 0.15))
	poly([j.shoulder + Vector2(-0.16, 0.0), j.shoulder + Vector2(0.15, 0.0), j.hip + Vector2(0.17, 0.0), j.hip + Vector2(-0.18, 0.0)], uni)
	limb(j.shoulder, j.elbow, 0.12, uni)
	limb(j.elbow, j.hand, 0.095, SKIN)
	var hd: Vector2 = j.head
	circle(hd.x, hd.y, 0.135, SKIN)
	line(hd.x + 0.04, hd.y - 0.05, hd.x + 0.15, hd.y - 0.05, 0.035, Color(0.1, 0.1, 0.1))     # big moustache
	circle(hd.x + 0.18, hd.y - 0.08, 0.03, CHROME)                                          # whistle
	if hat_off <= 0.0:
		poly([hd + Vector2(-0.16, 0.06), hd + Vector2(0.24, 0.06), hd + Vector2(0.14, 0.13), hd + Vector2(0.12, 0.22), hd + Vector2(-0.12, 0.22)], Color(0.97, 0.97, 0.97))
	else:
		var f := 1.6 - hat_off
		var hp := hd + Vector2(-f * 1.2, 0.3 + f * 1.5 - f * f * 0.8)
		poly([hp + Vector2(-0.16, 0.0), hp + Vector2(0.24, 0.0), hp + Vector2(0.12, 0.15), hp + Vector2(-0.12, 0.15)], Color(0.97, 0.97, 0.97))


## Ammi on the rooftop. throw: 0..1 through the throwing motion.
func ammi(throw: float, t: float) -> void:
	var suit := Color(0.75, 0.2, 0.45)
	var dup := Color(0.2, 0.6, 0.35)
	limb(Vector2(-0.1, 0.8), Vector2(-0.1, 0.0), 0.14, suit.darkened(0.2))
	limb(Vector2(0.1, 0.8), Vector2(0.1, 0.0), 0.14, suit.darkened(0.2))
	poly([Vector2(-0.26, 0.55), Vector2(0.26, 0.55), Vector2(0.22, 1.45), Vector2(-0.22, 1.45)], suit)
	var arm := lerpf(-0.6, 2.4, throw)
	limb(Vector2(0.18, 1.38), Vector2(0.18 + cos(arm) * 0.55, 1.38 + sin(arm) * 0.55), 0.1, SKIN)
	limb(Vector2(-0.18, 1.38), Vector2(-0.35, 1.0), 0.1, SKIN)    # hand on hip
	circle(0.0, 1.62, 0.15, SKIN)
	poly([Vector2(-0.2, 1.5), Vector2(-0.17, 1.76), Vector2(0.0, 1.84), Vector2(0.17, 1.76), Vector2(0.2, 1.5), Vector2(0.3, 1.1), Vector2(-0.3, 1.1)], dup)
	circle(0.0, 1.6, 0.12, SKIN)
	# Angry eyebrows.
	line(-0.08, 1.66, -0.02, 1.62, 0.025, Color(0.1, 0.05, 0.05))
	line(0.08, 1.66, 0.02, 1.62, 0.025, Color(0.1, 0.05, 0.05))
	ellipse(0.0, 1.53, 0.04, 0.03 + absf(sin(t * 8.0)) * 0.02, Color(0.35, 0.05, 0.05))


func chappal(spin: float) -> void:
	rot = spin
	poly([Vector2(-0.16, -0.05), Vector2(0.14, -0.06), Vector2(0.18, 0.0), Vector2(0.14, 0.06), Vector2(-0.16, 0.05), Vector2(-0.19, 0.0)], Color(0.45, 0.25, 0.1))
	line(0.02, -0.05, 0.06, 0.06, 0.03, Color(0.75, 0.15, 0.1))
	rot = 0.0
