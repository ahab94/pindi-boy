extends Node2D
## Draws the ride from an angle: a side view where depth across the road
## slides up and to the right (an "oblique" projection). That way a wheelie
## reads in profile, while buildings, vans and buses still show a front, a
## top and a side, which gives the 2D street its depth.
##
## Godot note: a Node2D draws in _draw(), which only runs when asked, so
## _process() calls queue_redraw() every frame. All drawing happens in one
## pass, painter style: sky, then far things, then near things.

const World := preload("res://scripts/world.gd")
const Ride := preload("res://scripts/ride.gd")
const Art := preload("res://scripts/art.gd")

const HERO := 1.3            # bikes and riders are drawn this much bigger: readable at a glance
const OX := 0.42             # how far right one metre of depth moves a point
const OY := 0.5              # how far up
const SKIES := {
	# top, horizon, light tint over the whole street
	"morning": [Color(0.52, 0.76, 0.95), Color(0.99, 0.9, 0.72), Color(1, 1, 1)],
	"noon": [Color(0.38, 0.66, 0.95), Color(0.85, 0.92, 0.98), Color(1, 1, 1)],
	"golden": [Color(0.45, 0.55, 0.85), Color(1.0, 0.76, 0.45), Color(1.0, 0.93, 0.82)],
	"rain": [Color(0.4, 0.44, 0.5), Color(0.62, 0.66, 0.7), Color(0.78, 0.8, 0.85)],
	"dusk": [Color(0.3, 0.24, 0.52), Color(0.98, 0.58, 0.42), Color(0.92, 0.82, 0.8)],
	"evening": [Color(0.12, 0.12, 0.3), Color(0.82, 0.45, 0.38), Color(0.72, 0.68, 0.78)],
}

var ride
var art := Art.new()
var S := 46.0                # pixels per metre
var cam_x := 0.0
var oy := 600.0              # screen y of the near kerb at road level
var portrait := false
var zoom := 1.0              # footage: closer camera
var shake := 0.0
var particles: Array = []
var _seen := 0
var _cam_lift := 0.0
var _size := Vector2(1280, 720)
var _tint := Color(1, 1, 1)
var _last_throw := -9.0
var _rng := RandomNumberGenerator.new()
var _joints := {}            # Shani's current (blended) pose
var _squash := 0.0           # landing squash, decays fast


const PX_PER_M := 64.0       # texture pixels per world metre
var _asphalt: ImageTexture
var _paving: ImageTexture
var _plaster: ImageTexture


## Surface textures are generated once from noise when the game starts:
## asphalt grain, paving slabs, and plaster with rain stains. Drawn with
## texture_repeat on, so one small tile covers the whole street.
func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_asphalt = _make_texture("asphalt", 11)
	_paving = _make_texture("paving", 23)
	_plaster = _make_texture("plaster", 37)


static func _make_texture(kind: String, seed: int) -> ImageTexture:
	var size := 256
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 5
	n.frequency = 0.02 if kind != "asphalt" else 0.05
	var noise := n.get_seamless_image(size, size)
	var fine := FastNoiseLite.new()
	fine.seed = seed + 1
	fine.frequency = 0.3
	var grain := fine.get_seamless_image(size, size)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for y in size:
		for x in size:
			var v := noise.get_pixel(x, y).r
			var g := grain.get_pixel(x, y).r
			var c := 1.0
			match kind:
				"asphalt":
					c = 0.82 + v * 0.18 + (g - 0.5) * 0.22
				"paving":
					var tx := x % 16
					var ty := (y + (8 if (x / 16) % 2 == 1 else 0)) % 16
					var joint := tx < 1 or ty < 1
					c = 0.92 + v * 0.08 + (g - 0.5) * 0.06 - (0.14 if joint else 0.0)
				"plaster":
					c = 0.88 + v * 0.12 + (g - 0.5) * 0.06
			img.set_pixel(x, y, Color(c, c, c))
	# Speckles: stones in the asphalt, chips in the paving, stains on walls.
	for i in (900 if kind == "asphalt" else 140):
		var px := rng.randi() % size
		var py := rng.randi() % size
		var lift := rng.randf_range(-0.25, 0.2)
		var base := img.get_pixel(px, py)
		img.set_pixel(px, py, Color(base.r + lift, base.g + lift, base.b + lift))
	if kind == "plaster":
		# Streaks where the rain runs down from the parapet.
		for i in 10:
			var sx := rng.randi() % size
			var w := rng.randi_range(2, 6)
			for y in size:
				var fade := 1.0 - float(y) / size
				for dx in w:
					var q := img.get_pixel((sx + dx) % size, y)
					img.set_pixel((sx + dx) % size, y, q.darkened(0.12 * fade))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A world-space quad with a texture laid on it. uv_axes picks which world
## axes map to the texture: "xd" for the ground, "xh" for walls.
func _tex_quad(pts: Array, tex: Texture2D, cols: PackedColorArray, axes := "xd") -> void:
	var screen := PackedVector2Array()
	var uvs := PackedVector2Array()
	for q in pts:
		screen.append(P(q.x, q.y, q.z))
		var u: float = q.x
		var v: float = q.y if axes == "xd" else -q.z
		uvs.append(Vector2(u, v) * PX_PER_M / float(tex.get_width()))
	draw_polygon(screen, cols, uvs, tex)


func _process(delta: float) -> void:
	if ride == null:
		return
	_layout()
	_apply_zoom()
	_follow_camera(delta)
	_read_events()
	_step_particles(delta)
	shake = maxf(0.0, shake - delta * 30.0)
	queue_redraw()


func reset() -> void:
	particles.clear()
	_seen = 0
	_last_throw = -9.0
	cam_x = -999.0


func _layout() -> void:
	_size = get_viewport_rect().size
	portrait = _size.y > _size.x
	if portrait:
		S = 54.0
		oy = _size.y * 0.76
	else:
		S = 62.0
		oy = _size.y - 56.0


## Shani sits about a third of the way across, a little further left the
## faster he goes, so you see more of what's coming.
func _apply_zoom() -> void:
	S *= zoom
	if zoom > 1.0:
		oy += (_size.y - oy) * (zoom - 1.0) * 1.2


func _follow_camera(delta: float) -> void:
	var x: float = ride.x
	var d: float = ride.d
	var screen_at := _size.x * (0.24 if portrait else 0.26) - minf(float(ride.v), 20.0) * 3.0
	var want := x + (d * S * OX - screen_at) / S
	if cam_x < -900.0:
		cam_x = want
	cam_x = lerpf(cam_x, want, minf(1.0, delta * 6.0))
	var lift: float = maxf(0.0, float(ride.h) - 0.8) * S * 0.6
	_cam_lift = lerpf(_cam_lift, lift, minf(1.0, delta * 5.0))


## World (x along, d across, h up) to screen.
func P(x: float, d: float, h: float) -> Vector2:
	var jig := Vector2(sin(ride.t * 70.0), cos(ride.t * 63.0)) * shake if ride else Vector2.ZERO
	return Vector2((x - cam_x) * S + d * S * OX, oy + _cam_lift - d * S * OY - h * S) + jig


# ---------------------------------------------------------------- events -> particles

func _read_events() -> void:
	for i in range(_seen, ride.events.size()):
		var ev := String(ride.events[i][1])
		var words := ev.split(" ")
		var x: float = ride.x
		var d: float = ride.d
		match words[0]:
			"pop":
				shake = maxf(shake, 4.0)
				for k in 10:
					_spawn(Vector3(x - 0.4, d, 0.42), Vector3(randf_range(-4, -1), randf_range(-0.5, 0.5), randf_range(0, 1.5)),
						0.5, Color(1, randf_range(0.4, 0.8), 0.1), 0.12, "spark")
				for k in 6:
					_spawn(Vector3(x - 0.5, d, 0.45), Vector3(randf_range(-2, -0.5), 0, randf_range(0.3, 1.0)),
						1.0, Color(0.25, 0.25, 0.28, 0.7), 0.3, "smoke")
			"crash":
				shake = maxf(shake, 14.0)
				var cause := words[1] if words.size() > 1 else ""
				for k in 14:
					_spawn(Vector3(x + 0.8, d, 0.3), Vector3(randf_range(-2, 5), randf_range(-1, 1), randf_range(1, 5)),
						0.8, Color(0.75, 0.68, 0.55, 0.8), 0.18, "dust")
				for k in 8:
					_spawn(Vector3(x + 0.5, d, 0.1), Vector3(randf_range(2, 7), randf_range(-0.5, 0.5), randf_range(0, 2)),
						0.4, Color(1, 0.85, 0.3), 0.06, "spark")
				if cause == "cart":
					for k in 16:
						_spawn(Vector3(x + 1.5, d, 1.0), Vector3(randf_range(-3, 6), randf_range(-1.5, 1.5), randf_range(2, 7)),
							1.6, [Color(1, 0.55, 0.05), Color(0.95, 0.85, 0.15), Color(0.85, 0.1, 0.15)][k % 3], 0.13, "fruit")
				elif cause == "eggs":
					for k in 18:
						_spawn(Vector3(x + 1.5, d, 1.0), Vector3(randf_range(-3, 6), randf_range(-1.5, 1.5), randf_range(2, 7)),
							1.6, [Color(1, 0.85, 0.1), Color(1, 1, 0.95), Color(0.92, 0.68, 0.3)][k % 3], 0.12, "fruit")
			"land":
				_squash = 0.22
				shake = maxf(shake, 3.0)
				for k in 8:
					_spawn(Vector3(x + 0.3, d, 0.05), Vector3(randf_range(-3, 1), randf_range(-0.8, 0.8), randf_range(0.2, 1.2)),
						0.6, Color(0.75, 0.68, 0.55, 0.7), 0.16, "dust")
			"pigeons":
				for k in 14:
					_spawn(Vector3(x + 4.0, d, 0.4), Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(0.5, 2.5)),
						2.0, Color(0.85, 0.86, 0.9), 0.08, "feather")
			"splash":
				for k in 16:
					_spawn(Vector3(x + 0.6, d, 0.1), Vector3(randf_range(-2, 3), randf_range(-1.5, 1.5), randf_range(1.5, 4)),
						0.7, Color(0.6, 0.75, 0.9, 0.8), 0.07, "drop")
			"chappal":
				shake = maxf(shake, 6.0)
				for k in 8:
					_spawn(Vector3(x + 0.6, d, 1.8), Vector3(randf_range(-2, 2), 0, randf_range(0, 3)),
						0.6, Color(1, 0.9, 0.2), 0.1, "spark")
			"bank":
				if words.size() > 1 and int(words[1]) >= 1000:
					for k in 24:
						_spawn(Vector3(x + 0.5, d, 2.5), Vector3(randf_range(-4, 4), randf_range(-1, 1), randf_range(2, 6)),
							1.5, Color.from_hsv(randf(), 0.8, 1.0), 0.08, "confetti")
			"throw":
				_last_throw = ride.t
	_seen = ride.events.size()


func _spawn(pos: Vector3, vel: Vector3, life: float, col: Color, size: float, kind: String) -> void:
	if particles.size() > 400:
		return
	particles.append({"p": pos, "v": vel, "life": life, "max": life, "col": col, "size": size, "kind": kind,
		"spin": randf() * TAU})


func _step_particles(delta: float) -> void:
	for q in particles:
		var vel: Vector3 = q.v
		var g := 9.0
		match String(q.kind):
			"smoke":
				g = -1.0
			"feather", "confetti":
				g = 1.5
				vel.x *= 0.98
		vel.z -= g * delta
		var pos: Vector3 = q.p + vel * delta
		if pos.z < 0.0 and q.kind != "smoke":
			pos.z = 0.0
			vel = Vector3(vel.x * 0.4, vel.y * 0.4, -vel.z * 0.25)
		q.p = pos
		q.v = vel
		q.life = float(q.life) - delta
		q.spin = float(q.spin) + delta * 8.0
	particles = particles.filter(func(q) -> bool: return float(q.life) > 0.0)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if ride == null:
		return
	art.c = self
	art.view = self
	art.s = S
	var sky: Array = SKIES.get(String(ride.level.get("sky", "noon")), SKIES.noon)
	_tint = sky[2]
	var x0 := cam_x - 14.0
	var x1 := cam_x + _size.x / S + 2.0
	_sky(sky)
	_skyline(sky)
	_buildings(x0, x1)
	_ammi()
	_road(x0, x1)
	_trees(x0, x1)
	_poles(x0, x1)
	_crowd(x0, x1)
	_decals(x0, x1)
	art.ink = 1.3
	art.shade = 0.16
	_actors(x0, x1)
	art.ink = 0.0
	art.shade = 0.0
	_draw_particles()
	_popups()
	_bubbles()
	if ride.level.get("rain", false):
		_rain()


func _c(col: Color) -> Color:
	return Color(col.r * _tint.r, col.g * _tint.g, col.b * _tint.b, col.a)


func _sky(sky: Array) -> void:
	var top: Color = sky[0]
	var low: Color = sky[1]
	var horizon := P(cam_x, World.FAR_WALK + 8.0, 0.0).y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(_size.x, 0), Vector2(_size.x, horizon), Vector2(0, horizon)]),
		PackedColorArray([top, top, low, low]))
	draw_rect(Rect2(0, horizon, _size.x, _size.y - horizon), low)
	# The sun (or moon), low and big.
	var sun_col := Color(1, 0.97, 0.8, 0.9)
	if ride.level.sky in ["dusk", "evening"]:
		sun_col = Color(1, 0.65, 0.4, 0.9)
	if ride.level.sky != "rain":
		draw_circle(Vector2(_size.x * 0.78, horizon - _size.y * 0.42), 46.0, sun_col)
	# Clouds, drifting slower than everything else.
	if ride.level.sky != "evening":
		for i in 6:
			var hs := absi(hash(i * 977 + 5))
			var cx := fmod(float(hs % 3000) - cam_x * S * 0.04 + ride.t * 6.0, _size.x + 600.0) - 300.0
			var cy := horizon - _size.y * (0.35 + float((hs >> 4) % 40) / 100.0)
			var cw := 90.0 + float((hs >> 8) % 120)
			var cc := Color(1, 1, 1, 0.75) if ride.level.sky != "rain" else Color(0.75, 0.77, 0.8, 0.85)
			for k in 7:
				var kx := cx + (k - 3) * cw * 0.22
				var kr := cw * (0.28 - absf(k - 3) * 0.04)
				draw_circle(Vector2(kx, cy - kr * 0.4), kr, cc)
			draw_rect(Rect2(cx - cw * 0.8, cy - 4.0, cw * 1.6, 10.0), cc.darkened(0.06))
	# A couple of crows.
	for i in 3:
		var bx := fmod(ride.t * 22.0 + i * 260.0, _size.x + 100.0) - 50.0
		var by := horizon - _size.y * (0.5 + 0.06 * i)
		var flap := sin(ride.t * 9.0 + i) * 5.0
		draw_polyline(PackedVector2Array([Vector2(bx - 8, by - flap), Vector2(bx, by), Vector2(bx + 8, by - flap)]), Color(0.1, 0.1, 0.1, 0.7), 2.0)


## Far-off rooftops that drift slowly: parallax sells the depth.
func _skyline(sky: Array) -> void:
	var low: Color = sky[1]
	var haze := low.darkened(0.18)
	var base := P(cam_x, World.FAR_WALK + 9.0, 0.0).y
	var shift := cam_x * S * 0.22
	# A line of hills right at the back.
	var hills := PackedVector2Array()
	for i in 41:
		var sx := _size.x * i / 40.0
		hills.append(Vector2(sx, base - 230.0 - 50.0 * sin((sx + shift * 0.4) * 0.006) - 25.0 * sin((sx + shift * 0.4) * 0.017)))
	hills.append(Vector2(_size.x, base))
	hills.append(Vector2(0, base))
	draw_colored_polygon(hills, low.darkened(0.08).lerp(Color(0.4, 0.5, 0.45), 0.25))
	var w := 70.0
	var first := int(floor(shift / w)) - 1
	for i in range(first, first + int(_size.x / w) + 3):
		var hsh := absi(hash(i)) % 1000
		var bh := 60.0 + (hsh % 7) * 22.0
		var sx := i * w - shift
		draw_rect(Rect2(sx, base - bh, w - 4.0, bh), haze)
		if hsh % 3 == 0:
			draw_rect(Rect2(sx + 12.0, base - bh - 16.0, 18.0, 16.0), haze.darkened(0.1))
		if hsh % 4 == 1:
			draw_line(Vector2(sx + 40.0, base - bh), Vector2(sx + 40.0, base - bh - 30.0), haze.darkened(0.1), 2.0)


func _buildings(x0: float, x1: float) -> void:
	var t: float = ride.t
	var evening := String(ride.level.sky) in ["dusk", "evening"]
	for b in ride.buildings:
		var bx0: float = b.x0
		var bx1: float = b.x1
		if bx1 < x0 - 10.0 or bx0 > x1:
			continue
		var d0: float = World.FAR_WALK + float(b.setback)
		var bh: float = b.h
		var wall: Color = _c(b.color)
		art.box(bx0, bx1, d0, d0 + 6.0, 0.0, bh, wall, _c(Color(0.66, 0.63, 0.6)))
		# Plaster texture over the front, darker towards the street (dust,
		# splashes, posters' glue).
		var grime := wall.darkened(0.32)
		_tex_quad([Vector3(bx0, d0, 0.0), Vector3(bx1, d0, 0.0), Vector3(bx1, d0, bh), Vector3(bx0, d0, bh)], _plaster,
			PackedColorArray([grime, grime, wall.lightened(0.04), wall.lightened(0.04)]), "xh")
		_tex_quad([Vector3(bx1, d0, 0.0), Vector3(bx1, d0 + 6.0, 0.0), Vector3(bx1, d0 + 6.0, bh), Vector3(bx1, d0, bh)], _plaster,
			PackedColorArray([grime.darkened(0.3), grime.darkened(0.3), wall.darkened(0.25), wall.darkened(0.25)]), "xh")
		var w := bx1 - bx0
		art.pen(P(bx0, d0, 0.0), S)
		# Parapet, with a drip line under it.
		art.rect(0.0, bh - 0.35, w, bh, wall.darkened(0.12))
		art.rect(0.0, bh - 0.42, w, bh - 0.35, wall.darkened(0.3))
		# Old posters and a painted wall ad between the floors.
		var hs0 := absi(int(b.seed))
		if hs0 % 3 == 0 and w > 5.5:
			art.rect(w - 1.6, 3.65, w - 0.6, 4.95, _c(Color(0.95, 0.92, 0.8)))
			art.rect(w - 1.5, 4.5, w - 0.7, 4.85, _c(Color(0.85, 0.15, 0.15)))
			art.rect(w - 1.5, 3.8, w - 0.7, 4.35, _c(Color(0.2, 0.3, 0.6)))
		# Ground floor: an open shop or a rolled-down shutter.
		if b.shutter:
			art.rect(0.3, 0.0, w - 0.3, 2.55, _c(Color(0.62, 0.64, 0.66)))
			for i in 9:
				art.line(0.3, 0.25 + i * 0.27, w - 0.3, 0.25 + i * 0.27, 0.03, _c(Color(0.48, 0.5, 0.52)))
		else:
			art.rect(0.3, 0.0, w - 0.3, 2.55, _c(Color(0.16, 0.12, 0.1)))
			_shop_goods(w, int(b.seed), String(b.sign))
			# Awning.
			art.poly([Vector2(0.2, 2.55), Vector2(w - 0.2, 2.55), Vector2(w - 0.1, 2.3), Vector2(0.1, 2.3)], _c(Color(0.85, 0.2, 0.2)))
		# The signboard.
		var sc: Color = _c(b.sign_color)
		art.rect(0.15, 2.65, w - 0.15, 3.5, sc)
		art.rect(0.15, 2.65, w - 0.15, 2.72, sc.lightened(0.3))
		_sign_text(String(b.sign), w, sc)
		# Upper floors: windows with grills, maybe a balcony and an AC unit.
		for f in range(1, int(b.floors)):
			var fy := 3.9 + (f - 1) * 3.0
			var n := maxi(1, int(w / 2.4))
			for i in n:
				var wx := (w - n * 2.4) / 2.0 + i * 2.4 + 0.6
				var lit := evening and (hash(int(b.seed) + f * 7 + i) % 3 == 0)
				var glass := Color(1, 0.85, 0.45) if lit else _c(Color(0.25, 0.33, 0.42))
				art.rect(wx - 0.08, fy - 0.08, wx + 1.28, fy + 1.48, wall.darkened(0.25))
				art.rect(wx, fy, wx + 1.2, fy + 1.4, glass)
				for g in 4:
					art.line(wx + 0.24 * (g + 1), fy, wx + 0.24 * (g + 1), fy + 1.4, 0.03, _c(Color(0.2, 0.2, 0.2)))
			if b.ac and f == 1:
				art.rect(w - 1.3, fy + 1.6, w - 0.4, fy + 2.15, _c(Color(0.9, 0.9, 0.88)))
				art.circle(w - 0.85, fy + 1.87, 0.18, _c(Color(0.6, 0.6, 0.62)))
		if b.balcony:
			art.box(bx0 + 0.8, bx1 - 0.8, d0 - 0.9, d0, 3.75, 3.9, wall.darkened(0.08))
			art.pen(P(bx0, d0 - 0.9, 0.0), S)
			for i in int((w - 1.6) / 0.3) + 1:
				art.line(0.8 + i * 0.3, 3.9, 0.8 + i * 0.3, 4.75, 0.03, _c(Color(0.25, 0.25, 0.25)))
			art.line(0.8, 4.75, w - 0.8, 4.75, 0.05, _c(Color(0.25, 0.25, 0.25)))
			# Washing on the line.
			for i in 3:
				var cx := 1.2 + i * 0.9
				if cx < w - 1.0:
					art.rect(cx, 4.8, cx + 0.6, 5.45 + sin(t * 2.0 + i) * 0.04, _c(Color.from_hsv(float(i) / 3.0 + float(int(b.seed) % 10) / 10.0, 0.5, 0.95)))
		# Rooftop: the water tank and the dish.
		if b.tank:
			var tx := bx0 + w * 0.3
			art.box(tx, tx + 1.3, d0 + 2.0, d0 + 3.3, bh, bh + 1.4, _c(Color(0.12, 0.12, 0.13)), _c(Color(0.22, 0.22, 0.24)))
		if b.dish:
			var dp := P(bx0 + w * 0.75, d0 + 1.5, bh + 0.9)
			draw_line(P(bx0 + w * 0.75, d0 + 1.5, bh), dp, _c(Color(0.5, 0.5, 0.5)), 3.0)
			draw_circle(dp, 0.45 * S, _c(Color(0.85, 0.85, 0.85)))
			draw_circle(dp + Vector2(4, -2), 0.3 * S, _c(Color(0.7, 0.7, 0.72)))


## What's inside an open shop: shelves of bottles, jars and boxes, crisp
## packets hanging in strips from the awning, and the owner at the counter.
func _shop_goods(w: float, seed: int, sign: String) -> void:
	var wood := _c(Color(0.45, 0.3, 0.18))
	art.rect(0.3, 2.3, w - 0.3, 2.55, _c(Color(0.25, 0.2, 0.16)))
	for row in 3:
		var sy := 0.95 + row * 0.5
		art.rect(0.4, sy - 0.04, w - 0.4, sy, wood)
		var xx := 0.45
		var k := 0
		while xx < w - 0.6:
			var hs := absi(hash(seed + row * 101 + k))
			var kind := hs % 4
			var col := _c(Color.from_hsv(float(hs % 97) / 97.0, 0.55 + float(hs % 3) * 0.1, 0.85))
			match kind:
				0:      # a bottle
					art.rect(xx, sy, xx + 0.1, sy + 0.32, col)
					art.rect(xx + 0.03, sy + 0.32, xx + 0.07, sy + 0.4, col.darkened(0.3))
					xx += 0.14
				1:      # a box with a label
					art.rect(xx, sy, xx + 0.28, sy + 0.3, col)
					art.rect(xx + 0.04, sy + 0.1, xx + 0.24, sy + 0.18, _c(Color(1, 1, 1, 0.7)))
					xx += 0.31
				2:      # a jar
					art.rect(xx, sy, xx + 0.18, sy + 0.24, _c(Color(0.8, 0.85, 0.85, 0.7)))
					art.rect(xx + 0.02, sy, xx + 0.16, sy + 0.16, col)
					art.rect(xx, sy + 0.24, xx + 0.18, sy + 0.28, col.darkened(0.4))
					xx += 0.21
				_:      # a stack of packets
					for q in 3:
						art.rect(xx, sy + q * 0.1, xx + 0.24, sy + q * 0.1 + 0.08, col.lightened(q * 0.1))
					xx += 0.27
			k += 1
	# Crisp packets hanging in strips at the front.
	for i in int(w / 1.3):
		var hx := 0.6 + i * 1.3
		var hs := absi(hash(seed * 7 + i))
		var col := _c(Color.from_hsv(float(hs % 100) / 100.0, 0.7, 0.95))
		art.line(hx + 0.09, 2.3, hx + 0.09, 1.3, 0.01, _c(Color(0.3, 0.3, 0.3)))
		for q in 5:
			art.rect(hx, 2.2 - q * 0.19, hx + 0.18, 2.36 - q * 0.19, col if q % 2 == 0 else col.lightened(0.25))
	# The owner behind the counter, unimpressed.
	var ox := w * 0.5
	art.rect(ox - 0.9, 0.0, ox + 0.9, 0.85, wood.darkened(0.1))
	art.rect(ox - 0.95, 0.85, ox + 0.95, 0.92, wood.lightened(0.15))
	art.rect(ox - 0.24, 0.92, ox + 0.24, 1.35, _c(Color(0.92, 0.92, 0.88)))
	art.circle(ox, 1.52, 0.17, _c(Color(0.72, 0.5, 0.34)))
	art.rect(ox - 0.16, 1.62, ox + 0.16, 1.7, _c(Color(0.15, 0.12, 0.1)))
	art.line(ox - 0.08, 1.44, ox + 0.08, 1.44, 0.035, _c(Color(0.15, 0.1, 0.08)))
	art.circle(ox - 0.06, 1.55, 0.02, _c(Color(0.1, 0.1, 0.1)))
	art.circle(ox + 0.06, 1.55, 0.02, _c(Color(0.1, 0.1, 0.1)))


func _sign_text(msg: String, w: float, bg: Color) -> void:
	var font := ThemeDB.fallback_font
	var px := int(0.52 * S)
	var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if tw > (w - 0.5) * S:
		px = int(px * (w - 0.5) * S / tw)
		tw = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := art.p(w / 2.0, 3.07) + Vector2(-tw / 2.0, px * 0.36)
	var fg := Color(1, 1, 1) if bg.get_luminance() < 0.55 else Color(0.1, 0.1, 0.1)
	draw_string(font, at, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, fg)


func _ammi() -> void:
	if not ride.level.get("chappals", false) or ride.t < 0.0:
		return
	var ax: float = ride.ammi_x
	# Her balcony slides along with her (she's very determined).
	art.box(ax - 1.2, ax + 1.2, Ride.AMMI_D - 0.5, World.FAR_WALK, Ride.AMMI_H - 0.15, Ride.AMMI_H, _c(Color(0.85, 0.8, 0.72)))
	art.pen(P(ax, Ride.AMMI_D, Ride.AMMI_H), S)
	var throw := clampf((ride.t - _last_throw) / 0.35, 0.0, 1.0)
	art.ammi(throw if throw < 1.0 else 0.0, ride.t)


## Electricity poles and the famous tangle of wires.
func _poles(x0: float, x1: float) -> void:
	var poles: Array = ride.poles
	var wire := Color(0.08, 0.08, 0.08, 0.85)
	for i in poles.size():
		var pl: Dictionary = poles[i]
		var px: float = pl.x
		if px < x0 - 40.0 or px > x1 + 20.0:
			continue
		var top := P(px + float(pl.lean) * float(pl.h), 10.0, float(pl.h))
		draw_line(P(px, 10.0, 0.2), top, _c(Color(0.6, 0.6, 0.58)), 0.22 * S)
		draw_line(top + Vector2(-0.7, 0.2) * S, top + Vector2(0.7, -0.2) * S, _c(Color(0.35, 0.3, 0.25)), 0.1 * S)
		if hash(int(px)) % 3 == 0:
			var tb := P(px, 10.0, float(pl.h) - 2.0)
			draw_rect(Rect2(tb + Vector2(-0.35, -0.5) * S, Vector2(0.7, 1.0) * S), _c(Color(0.45, 0.48, 0.45)))
		if i + 1 < poles.size():
			var nx: Dictionary = poles[i + 1]
			var ntop := P(float(nx.x) + float(nx.lean) * float(nx.h), 10.0, float(nx.h))
			for k in 4:
				_sag(top + Vector2(-0.6 + k * 0.4, 0.1 * k) * S, ntop + Vector2(-0.6 + k * 0.4, 0.1 * k) * S, 0.6 * S + k * 6.0, wire)
		# Wires off to the houses, the more the merrier.
		for k in 3:
			var hx := px + 3.0 + k * 4.0
			_sag(top, P(hx, World.FAR_WALK, 4.5 + k * 0.8), 0.4 * S, wire)


func _sag(a: Vector2, b: Vector2, sag: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		pts.append(a.lerp(b, f) + Vector2(0, sag * 4.0 * f * (1.0 - f)))
	draw_polyline(pts, col, 1.5, true)


func _road(x0: float, x1: float) -> void:
	var wet: bool = ride.level.get("rain", false)
	var tar := _c(Color(0.36, 0.36, 0.38) if not wet else Color(0.26, 0.27, 0.3))
	# Far footpath, its painted kerb, the road, the near footpath.
	_flat(x0, x1, World.ROAD_W, World.FAR_WALK + 1.0, 0.2, _c(Color(0.72, 0.67, 0.58)), _paving)
	# Shade at the foot of the shop fronts.
	var ao := PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.32), Color(0, 0, 0, 0.32)])
	_tex_quad([Vector3(x0, World.FAR_WALK - 1.2, 0.2), Vector3(x1 + 12.0, World.FAR_WALK - 1.2, 0.2),
		Vector3(x1 + 12.0, World.FAR_WALK, 0.2), Vector3(x0, World.FAR_WALK, 0.2)], _paving, ao)
	var seg := 1.5
	var k0 := int(floor(x0 / seg))
	for k in range(k0, int(x1 / seg) + 2):
		var a := k * seg
		art._quad(P(a, World.ROAD_W, 0.0), P(a + seg, World.ROAD_W, 0.0), P(a + seg, World.ROAD_W, 0.2), P(a, World.ROAD_W, 0.2),
			_c(Color(0.95, 0.82, 0.1) if k % 2 == 0 else Color(0.12, 0.12, 0.12)))
		draw_line(P(a, World.ROAD_W, 0.2), P(a, World.FAR_WALK, 0.2), _c(Color(0.6, 0.55, 0.48)), 1.0)
	_flat(x0, x1, 0.0, World.ROAD_W, 0.0, tar, _asphalt)
	# Darker, oilier strips where the wheels go.
	for ld in [1.5, 4.5, 7.5]:
		_flat(x0, x1, ld - 0.45, ld + 0.45, 0.0, Color(0.0, 0.0, 0.0, 0.07))
	# Patches and cracks, the same every time you pass.
	var p0 := int(floor(x0 / 7.0))
	for k in range(p0, int(x1 / 7.0) + 2):
		var hs := absi(hash(k * 31 + 7))
		var px := k * 7.0 + (hs % 50) / 10.0
		var pd := 0.5 + (hs % 80) / 10.0
		if hs % 3 == 0:
			art._quad(P(px, pd, 0.0), P(px + 2.0, pd, 0.0), P(px + 2.2, pd + 1.2, 0.0), P(px + 0.2, pd + 1.2, 0.0), tar.darkened(0.12))
		elif hs % 3 == 1:
			draw_polyline(PackedVector2Array([P(px, pd, 0.0), P(px + 0.6, pd + 0.4, 0.0), P(px + 1.1, pd + 0.2, 0.0), P(px + 1.6, pd + 0.7, 0.0)]), tar.darkened(0.3), 1.5)
		if wet and hs % 2 == 0:
			art._quad(P(px, pd, 0.0), P(px + 3.0, pd, 0.0), P(px + 3.0, pd + 0.15, 0.0), P(px, pd + 0.15, 0.0), Color(0.75, 0.8, 0.9, 0.25))
	# Manhole covers, oil stains and somebody else's skid marks.
	for k in range(int(floor(x0 / 23.0)), int(x1 / 23.0) + 2):
		var hs := absi(hash(k * 53 + 11))
		var mx := k * 23.0 + (hs % 100) / 10.0
		var md := 0.8 + ((hs >> 6) % 75) / 10.0
		match hs % 4:
			0:
				art.ground_ellipse(mx, md, 0.45, 0.45, Color(0.18, 0.18, 0.2))
				art.ground_ellipse(mx, md, 0.38, 0.38, Color(0.32, 0.32, 0.34))
				for q in 3:
					draw_line(P(mx - 0.3, md - 0.15 + q * 0.15, 0.0), P(mx + 0.3, md - 0.15 + q * 0.15, 0.0), Color(0.2, 0.2, 0.22), 1.5)
			1:
				art.ground_ellipse(mx, md, 0.9, 0.4, Color(0.05, 0.05, 0.08, 0.22))
				art.ground_ellipse(mx + 0.2, md, 0.4, 0.2, Color(0.25, 0.1, 0.35, 0.12))
			2:
				for q in 2:
					var sd := md + q * 0.25
					draw_polyline(PackedVector2Array([P(mx, sd, 0.0), P(mx + 2.0, sd + 0.15, 0.0), P(mx + 4.5, sd + 0.05, 0.0)]), Color(0.08, 0.08, 0.08, 0.35), 4.0)
	# Lane dashes.
	var dash0 := int(floor(x0 / 6.0))
	for k in range(dash0, int(x1 / 6.0) + 2):
		for ld in [3.0, 6.0]:
			art._quad(P(k * 6.0, ld - 0.07, 0.0), P(k * 6.0 + 3.0, ld - 0.07, 0.0), P(k * 6.0 + 3.0, ld + 0.07, 0.0), P(k * 6.0, ld + 0.07, 0.0), _c(Color(0.92, 0.92, 0.88, 0.85)))
	_flat(x0, x1, World.NEAR_WALK, 0.0, 0.2, _c(Color(0.7, 0.65, 0.56)), _paving)
	# Below the near footpath: the open nala, then more pavement to the
	# bottom of the screen (portrait shows a lot of it).
	_flat(x0, x1, World.NEAR_WALK - 0.8, World.NEAR_WALK, 0.0, _c(Color(0.16, 0.2, 0.16)))
	_flat(x0, x1, World.NEAR_WALK - 0.75, World.NEAR_WALK - 0.05, 0.02, _c(Color(0.25, 0.32, 0.24)))
	_flat(x0, x1, -40.0, World.NEAR_WALK - 0.8, 0.2, _c(Color(0.62, 0.58, 0.5)), _paving)
	for k in range(int(floor(x0 / 2.0)), int(x1 / 2.0) + 6):
		draw_line(P(k * 2.0, World.NEAR_WALK - 0.8, 0.2), P(k * 2.0 - 30.0, -40.0, 0.2), _c(Color(0.55, 0.51, 0.44)), 1.0)
	_flat(x0, x1, -0.12, 0.0, 0.21, _c(Color(0.92, 0.92, 0.9)))
	# Shani's front door: the finish.
	var fx: float = ride.length
	if fx > x0 and fx < x1 + 10.0:
		for i in 9:
			var col := Color(1, 1, 1) if i % 2 == 0 else Color(0.1, 0.1, 0.1)
			art._quad(P(fx, i, 0.0), P(fx + 0.6, i, 0.0), P(fx + 0.6, i + 1.0, 0.0), P(fx, i + 1.0, 0.0), col)
		art.pen(P(fx + 0.3, World.FAR_WALK - 0.3, 0.0), S)
		art.line(-0.6, 0.0, -0.6, 3.6, 0.1, Color(0.4, 0.3, 0.2))
		art.line(0.6, 0.0, 0.6, 3.6, 0.1, Color(0.4, 0.3, 0.2))
		art.rect(-1.0, 3.0, 1.0, 3.8, Color(0.1, 0.5, 0.25))
		art.text(0.0, 3.4, "GHAR", 0.5, Color(1, 1, 1))


func _flat(x0: float, x1: float, d0: float, d1: float, h: float, col: Color, tex: Texture2D = null) -> void:
	if tex:
		_tex_quad([Vector3(x0, d0, h), Vector3(x1 + 12.0, d0, h), Vector3(x1 + 12.0, d1, h), Vector3(x0, d1, h)], tex, PackedColorArray([col]))
	else:
		art._quad(P(x0, d0, h), P(x1 + 12.0, d0, h), P(x1 + 12.0, d1, h), P(x0, d1, h), col)


## Neem trees: a trunk, a big leafy crown that sways, and dappled shade.
func _trees(x0: float, x1: float) -> void:
	var t: float = ride.t
	for tr in ride.trees:
		var tx: float = tr.x
		if tx < x0 - 6.0 or tx > x1 + 4.0:
			continue
		var th: float = tr.h
		var tr_r: float = tr.r
		var seed: int = tr.seed
		# Shade on the pavement and the edge of the road.
		for k in 5:
			var hs := absi(hash(seed + k))
			art.ground_ellipse(tx + 0.6 + (hs % 30) / 10.0 - 1.5, 9.4 + ((hs >> 4) % 20) / 10.0 - 1.0, tr_r * 0.6, 0.7, Color(0, 0.05, 0, 0.13), 0.2)
		art.pen(P(tx, 10.4, 0.2), S)
		art.ink = 1.2
		art.shade = 0.12
		art.limb(Vector2(0, 0), Vector2(0.15, th * 0.55), 0.32, _c(Color(0.42, 0.3, 0.2)))
		art.limb(Vector2(0.15, th * 0.5), Vector2(-0.7, th * 0.75), 0.16, _c(Color(0.42, 0.3, 0.2)))
		art.limb(Vector2(0.15, th * 0.5), Vector2(0.8, th * 0.8), 0.14, _c(Color(0.42, 0.3, 0.2)))
		art.ink = 0.0
		art.shade = 0.0
		var sway := sin(t * 1.3 + seed % 7) * 0.06
		var greens := [Color(0.2, 0.42, 0.18), Color(0.28, 0.52, 0.22), Color(0.36, 0.6, 0.26)]
		for layer in 3:
			for k in 9:
				var hs := absi(hash(seed * 31 + layer * 17 + k))
				var a := float(k) / 9.0 * TAU
				var rr := tr_r * (0.55 + float(hs % 40) / 100.0)
				var cx := cos(a) * tr_r * 0.75 + sway * (1.0 + layer) + layer * 0.12
				var cy := th + sin(a) * tr_r * 0.45 + layer * 0.18
				art.circle(cx, cy, rr * (0.62 - layer * 0.1), _c(greens[layer]))
		for k in 7:
			var hs := absi(hash(seed + 99 + k))
			art.circle(-tr_r * 0.5 + (hs % 100) / 100.0 * tr_r + sway * 3.0, th + tr_r * 0.15 + ((hs >> 7) % 50) / 100.0, 0.18, _c(Color(0.5, 0.72, 0.3, 0.8)))


func _crowd(x0: float, x1: float) -> void:
	for c in ride.crowd:
		var cx: float = c.x
		if cx < x0 - 6.0 or cx > x1:
			continue
		_soft_shadow(cx, float(c.d), 0.35, 0.22, 0.25)
		art.pen(P(cx, float(c.d), 0.2), S * 1.1)
		var cheer: bool = float(c.cheer) > 0.0
		art.ink = 1.2
		art.shade = 0.14
		art.person(int(c.look), ride.t * 8.0 if cheer else 0.0, false, cheer)
		art.ink = 0.0
		art.shade = 0.0


## Flat things on the road: potholes, puddles, breakers, fallen chappals,
## the landing rings for chappals in flight.
func _decals(x0: float, x1: float) -> void:
	var wet: bool = ride.level.get("rain", false)
	for o in ride.hazards:
		var ox: float = o.x
		if ox < x0 - 6.0 or ox > x1 + 4.0:
			continue
		var od: float = o.d
		match String(o.kind):
			"pothole":
				art.ground_ellipse(ox, od, 0.6, 0.55, _c(Color(0.28, 0.27, 0.27)))
				art.ground_ellipse(ox + 0.05, od + 0.05, 0.45, 0.4, Color(0.12, 0.11, 0.11) if not wet else Color(0.3, 0.38, 0.5))
			"puddle":
				art.ground_ellipse(ox, od, 1.7, 1.05, Color(0.42, 0.52, 0.66, 0.9))
				art.ground_ellipse(ox + 0.3, od + 0.2, 1.1, 0.6, Color(0.58, 0.68, 0.82, 0.8))
				draw_line(P(ox - 0.8, od + 0.3, 0.0), P(ox + 0.2, od + 0.3, 0.0), Color(1, 1, 1, 0.6), 2.0)
			"breaker":
				for i in 10:
					var da := i * 0.9
					var col := _c(Color(0.95, 0.8, 0.1) if i % 2 == 0 else Color(0.12, 0.12, 0.12))
					art._quad(P(ox - 0.4, da, 0.0), P(ox, da, 0.16), P(ox, da + 0.9, 0.16), P(ox - 0.4, da + 0.9, 0.0), col.lightened(0.1))
					art._quad(P(ox, da, 0.16), P(ox + 0.4, da, 0.0), P(ox + 0.4, da + 0.9, 0.0), P(ox, da + 0.9, 0.16), col.darkened(0.15))
	for ch in ride.chappals:
		if ch.landed:
			art.pen(P(float(ch.tx), float(ch.td), 0.02), S)
			art.chappal(0.3)
		else:
			# Where it's going to land: fair warning.
			var f: float = clampf((ride.t - float(ch.t0)) / Ride.CHAPPAL_FLIGHT, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(ride.t * 20.0)
			art.ground_ellipse(float(ch.tx), float(ch.td), 0.9 - f * 0.3, 0.7 - f * 0.2, Color(1, 0.15, 0.1, 0.15 + 0.15 * pulse))
			art.ground_ring(float(ch.tx), float(ch.td), 0.9 - f * 0.3, 0.7 - f * 0.2, Color(1, 0.15, 0.1, 0.6 + 0.4 * pulse), 4.0)


## Everything that stands up, sorted far to near.
func _actors(x0: float, x1: float) -> void:
	var list: Array = []
	for o in ride.hazards:
		var ox: float = o.x
		if ox < x0 - 8.0 or ox > x1 + 6.0:
			continue
		if o.kind in ["pothole", "puddle", "breaker"]:
			continue
		list.append([float(o.d), "hazard", o])
	list.append([float(ride.d) - 0.01, "bike", null])
	if not ride.warden.is_empty():
		list.append([float(ride.warden.d), "warden", ride.warden])
	for ch in ride.chappals:
		if not ch.landed:
			list.append([ride.chappal_pos(ch).y, "chappal", ch])
	list.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	for item in list:
		match String(item[1]):
			"hazard":
				_hazard(item[2])
			"bike":
				_bike()
			"warden":
				_warden(item[2])
			"chappal":
				var pos: Vector3 = ride.chappal_pos(item[2])
				art.ground_ellipse(pos.x, pos.y, 0.25, 0.15, Color(0, 0, 0, 0.25))
				art.pen(P(pos.x, pos.y, pos.z), S)
				art.chappal(ride.t * 12.0 * float(item[2].spin))


func _hazard(o: Dictionary) -> void:
	var ox: float = o.x
	var od: float = o.d
	var look: int = o.look
	var t: float = ride.t
	var kind := String(o.kind)
	var k: Dictionary = World.KINDS[kind]
	if k.solid and kind != "ped":
		_soft_shadow(ox, od, float(k.len) * 0.55, float(k.dep) * 0.5, 0.3)
	match kind:
		"cart", "eggs":
			art.cart(ox, od, kind == "eggs", look, t)
		"rickshaw":
			art.rickshaw(ox, od, 1.0, look, t)
		"wrongway":
			art.rickshaw(ox, od, -1.0, look, t)
		"wagon":
			art.wagon(ox, od, look, t)
		"bus":
			art.bus(ox, od, look, t)
		"baraat":
			art.baraat(ox, od, look, t)
		"ped":
			art.ground_ellipse(ox, od, 0.3, 0.2, Color(0, 0, 0, 0.22))
			art.pen(P(ox, od, 0.2 if not ride._on_road(o) else 0.0), S)
			var walking: bool = o.state == "walk" or o.state == "scared"
			art.person(look, t * (16.0 if o.state == "scared" else 8.0) if walking else 0.0, o.state == "scared")
		"goats":
			for i in 3:
				var gx := ox - 0.9 + i * 0.9
				var gd := od + (i - 1) * 0.35
				art.pen(P(gx, gd, 0.0), S, 0.0, 1.0 if (look + i) % 2 == 0 else -1.0)
				art.goat(look + i, t * 9.0 if o.state != "" and o.state != "done" else 0.0)
		"pigeons":
			var flying: bool = o.state == "fly"
			var since: float = t - float(o.get("fly_t", t))
			for i in 7:
				var hs := absi(hash(look * 13 + i))
				var px := ox - 1.2 + (hs % 25) / 10.0
				var pd := od - 0.9 + ((hs >> 5) % 18) / 10.0
				var ph := 0.0
				if flying:
					px += since * (2.0 + (hs % 5)) * (1.0 if hs % 2 == 0 else -0.6)
					pd += since * ((hs >> 3) % 3 - 1) * 0.8
					ph = since * (2.5 + (hs % 4) * 0.6)
					if ph > 12.0:
						continue
				art.pen(P(px, pd, ph), S, 0.0, 1.0 if hs % 2 == 0 else -1.0)
				art.pigeon(look + i, t, since if flying else 0.0)
		"ramp":
			var hl := float(k.len) / 2.0
			var hd := float(k.dep) / 2.0
			art.box(ox + hl - 0.7, ox + hl, od - hd + 0.1, od + hd - 0.1, 0.0, float(k.h) - 0.05, _c(Color(0.72, 0.3, 0.2)))
			art.pen(P(ox + hl - 0.7, od - hd + 0.1, 0.0), S)
			for row in 4:
				art.line(0.0, 0.22 * (row + 1), 0.7, 0.22 * (row + 1), 0.02, _c(Color(0.9, 0.85, 0.75)))
			art._quad(P(ox - hl, od - hd, 0.0), P(ox + hl, od - hd, float(k.h)), P(ox + hl, od + hd, float(k.h)), P(ox - hl, od + hd, 0.0), _c(Color(0.78, 0.6, 0.35)))
			art._quad(P(ox - hl, od - hd, 0.0), P(ox + hl, od - hd, float(k.h)), P(ox + hl, od - hd, float(k.h) - 0.08), P(ox - hl, od - hd, -0.08), _c(Color(0.55, 0.4, 0.22)))
			for i in 4:
				var f := (i + 1) / 5.0
				draw_line(P(ox - hl + f * 2.0 * hl, od - hd, f * float(k.h)), P(ox - hl + f * 2.0 * hl, od + hd, f * float(k.h)), _c(Color(0.6, 0.45, 0.25)), 1.5)


func _bike() -> void:
	var x: float = ride.x
	var d: float = ride.d
	var h: float = ride.h
	var t: float = ride.t
	var kind := String(ride.level.bike)
	var wheel := -x / 0.31
	if float(ride.crash_t) > 0.0:
		_crash_scene(kind, wheel)
		return
	# Blink while invulnerable after a crash.
	if float(ride.safe_t) > 0.0 and fmod(t, 0.2) < 0.1:
		return
	var shadow := clampf(1.0 - h * 0.2, 0.4, 1.0)
	_soft_shadow(x + 0.65, d, 1.05 * shadow, 0.38 * shadow, 0.38 * shadow)
	# Speed lines when he's flying.
	if float(ride.v) > 12.0:
		for i in 4:
			var ly := 0.4 + i * 0.4
			var len := (float(ride.v) - 10.0) * 0.25
			draw_line(P(x - 0.6 - len, d, h + ly), P(x - 0.6, d, h + ly), Color(1, 1, 1, 0.35), 2.0)
	var wobble := sin(t * 40.0) * 0.06 if float(ride.wobble_t) > 0.0 else 0.0
	# Flips turn the whole bike; a spin squashes it sideways and mirrors it
	# halfway round; a lane change leans it a touch.
	var lean := -float(ride.vd) * 0.025
	var angle := deg_to_rad(float(ride.pitch) + float(ride.flip)) + wobble + lean
	var spin_k := cos(deg_to_rad(float(ride.spin)))
	var mirror := (1.0 if spin_k >= 0.0 else -1.0) * maxf(absf(spin_k), 0.12)
	# Flip about the bike's middle (around the rider), not the back tyre.
	var mid := Vector2(0.65, 0.8)
	var pivot_shift := Vector2.ZERO
	if absf(float(ride.flip)) > 0.5:
		var a := deg_to_rad(float(ride.flip))
		var rotated := Vector2(mid.x * cos(a) - mid.y * sin(a), mid.x * sin(a) + mid.y * cos(a))
		pivot_shift = mid - rotated
	art.pen(P(x + pivot_shift.x * HERO, d, h + pivot_shift.y * HERO), S * HERO, angle, mirror)
	_squash = maxf(0.0, _squash - get_process_delta_time() * 2.0)
	art.sy = 1.0 - _squash - float(ride.jump_charge) * 0.12
	if float(ride.scene_t) > 0.0:
		_flames(t)
	var pose := String(ride.trick) if ride.trick != "" else ("crouch" if float(ride.jump_charge) > 0.05 else "ride")
	_blend_pose(pose)
	art.shani_back(pose)
	art.bike(kind, wheel, t, true, float(ride.v))
	art.shani_front(pose, t, float(ride.v), "yell" if ride.trick != "" or ride.airborne else "")
	art.pose_override = {}
	art.rot = 0.0
	art.sy = 1.0
	_bike_meters(x, d, h, t)


## Shani's joints ease toward the pose he's going for, so tricks flow
## instead of snapping.
func _blend_pose(target: String) -> void:
	var want: Dictionary = Art.POSES.get(target, Art.POSES.ride)
	if _joints.is_empty():
		_joints = want.duplicate()
	var f := 1.0 - exp(-get_process_delta_time() * 18.0)
	for k in want:
		_joints[k] = (_joints[k] as Vector2).lerp(want[k], f)
	art.pose_override = _joints


## SCENE ON: the silencer spits fire.
func _flames(t: float) -> void:
	for i in 3:
		var flick := 0.6 + 0.4 * sin(t * 40.0 + i * 2.1)
		var len := (0.35 + i * 0.12) * flick
		art.poly([Vector2(-0.38, 0.36), Vector2(-0.38 - len, 0.41 + sin(t * 30.0 + i) * 0.04), Vector2(-0.38, 0.47)],
			[Color(1, 0.85, 0.2, 0.9), Color(1, 0.5, 0.1, 0.85), Color(1, 0.2, 0.1, 0.7)][i])


## The wheelie gauge rides with the bike (eyes stay on the road), plus a
## ring that fills while a trick is being done.
func _bike_meters(x: float, d: float, h: float, t: float) -> void:
	var font := ThemeDB.fallback_font
	var pitch: float = ride.pitch
	var c := P(x - 1.1, d, h + 1.5)
	var r := 30.0 if not portrait else 34.0
	if pitch > 2.0 and not ride.airborne:
		draw_arc(c, r, PI, TAU, 24, Color(0, 0, 0, 0.55), 12.0)
		draw_arc(c, r, PI + deg_to_rad(Ride.SWEET.x), PI + deg_to_rad(Ride.SWEET.y), 12, Color(0.3, 0.95, 0.4), 9.0)
		draw_arc(c, r, PI + deg_to_rad(Ride.LET_GO_AT), TAU, 8, Color(1, 0.25, 0.2), 9.0)
		var a := PI + deg_to_rad(clampf(pitch, 0.0, 180.0))
		draw_line(c, c + Vector2(cos(a), sin(a)) * (r + 6.0), Color(1, 1, 1), 4.0)
		draw_circle(c, 5, Color(1, 1, 1))
		var danger: bool = pitch > Ride.LET_GO_AT - 4.0 or ride.assist_aim() > Ride.LET_GO_AT - 4.0
		if danger and fmod(t, 0.3) < 0.2:
			var msg := "LET GO!"
			var fs := 30 if not portrait else 34
			var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, c + Vector2(-tw / 2.0, -r - 14.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0.1, 0, 0))
			draw_string(font, c + Vector2(-tw / 2.0, -r - 14.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.3, 0.25))
	if String(ride.trick) != "":
		var tr: Dictionary = Ride.TRICKS[ride.trick]
		var f: float = clampf(float(ride.trick_t) / float(tr.time), 0.0, 1.0)
		var rc := P(x + 0.7, d, h + 1.3)
		var rr := 62.0 if not portrait else 70.0
		draw_arc(rc, rr, 0, TAU, 40, Color(0, 0, 0, 0.35), 8.0)
		draw_arc(rc, rr, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(1, 0.9, 0.3), 8.0)


## The fall: Shani cartwheels down the road while the bike skids on its side.
## A shadow with a soft edge: a few stacked ellipses, each fainter and wider.
func _soft_shadow(x: float, d: float, rx: float, rd: float, alpha: float) -> void:
	var save_ink := art.ink
	var save_shade := art.shade
	art.ink = 0.0
	art.shade = 0.0
	for k in 3:
		var grow := 1.0 + (2 - k) * 0.18
		art.ground_ellipse(x, d, rx * grow, rd * grow, Color(0, 0, 0, alpha * 0.4))
	art.ink = save_ink
	art.shade = save_shade


func _crash_scene(kind: String, wheel: float) -> void:
	var tc: float = Ride.CRASH_TIME - float(ride.crash_t)
	var phase := tc / Ride.CRASH_TIME
	var x: float = ride.x
	var d: float = ride.d
	var cv: float = ride.crash_v
	var backwards := String(ride.crash_cause) in ["looped", "backflop"]
	# Bike: a tumble, then lying flat and sliding.
	var bh := maxf(0.0, 0.7 * sin(minf(tc, 0.5) * TAU)) if tc < 0.5 else 0.0
	art.ground_ellipse(x + 0.65, d, 1.0, 0.35, Color(0, 0, 0, 0.25))
	art.pen(P(x, d, bh), S * HERO, (tc * 6.0 if backwards else -tc * 6.0) if tc < 0.5 else 0.0)
	if tc >= 0.5:
		art.sy = 0.45
	art.bike(kind, wheel, ride.t)
	art.sy = 1.0
	art.rot = 0.0
	# Shani flies further, lands, sees stars, gets up.
	var air := minf(tc, 0.76)
	var rx := x + 1.0 + air * cv * 0.45
	var rh := maxf(0.0, 1.0 + 4.0 * air - 7.0 * air * air)
	art.ground_ellipse(rx, d, 0.6, 0.25, Color(0, 0, 0, 0.25))
	art.pen(P(rx, d, rh), S * HERO)
	art.shani_tumble(phase, (-1.0 if not backwards else 1.0) * air * 14.0, ride.t)
	art.rot = 0.0


func _warden(w: Dictionary) -> void:
	var wx: float = w.x
	var wd: float = w.d
	if wx < cam_x - 12.0:
		return
	art.ground_ellipse(wx + 0.65, wd, 1.0, 0.35, Color(0, 0, 0, 0.28))
	art.pen(P(wx, wd, 0.0), S * HERO)
	art.bike("warden", -wx / 0.31, ride.t, false)
	art.warden_rider(ride.t, float(w.hat_t))
	# The blinking light on the back.
	var on := fmod(ride.t, 0.4) < 0.2
	art.circle(-0.1, 0.85, 0.08, Color(1, 0.15, 0.1) if on else Color(0.15, 0.3, 1))


func _draw_particles() -> void:
	for q in particles:
		var pos: Vector3 = q.p
		var col: Color = q.col
		var a: float = clampf(float(q.life) / float(q.max) * 1.5, 0.0, 1.0)
		col.a *= a
		var sp := P(pos.x, pos.y, pos.z)
		var r: float = float(q.size) * S
		match String(q.kind):
			"smoke":
				r *= 1.0 + (1.0 - float(q.life) / float(q.max)) * 2.0
				draw_circle(sp, r, col)
			"spark", "drop":
				var vel: Vector3 = q.v
				draw_line(sp, sp - Vector2(vel.x + vel.y * OX, -vel.z - vel.y * OY) * 0.03 * S, col, maxf(1.5, r * 0.6))
			"feather", "confetti":
				var sp2 := Vector2(cos(float(q.spin)), sin(float(q.spin))) * r
				draw_line(sp - sp2, sp + sp2, col, maxf(2.0, r * 0.5))
			_:
				draw_circle(sp, r, col)


func _popups() -> void:
	var font := ThemeDB.fallback_font
	for pp in ride.popups:
		var age: float = ride.t - float(pp.t0)
		var px0: float = float(pp.x) + (float(ride.x) if pp.get("rel", false) else 0.0)
		var pd0: float = float(ride.d) if pp.get("rel", false) else float(pp.d)
		var sp := P(px0, pd0, float(pp.h) + age * 1.4)
		var grow := minf(1.0, age * 8.0)
		var px := int((26.0 if not portrait else 28.0) * (0.6 + 0.4 * grow))
		var msg := String(pp.text)
		var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var col: Color = pp.col
		col.a = clampf(1.4 - age, 0.0, 1.0)
		var at := sp - Vector2(tw / 2.0, 0)
		draw_string_outline(font, at, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0.1, 0.05, 0.05, col.a))
		draw_string(font, at, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _bubbles() -> void:
	var font := ThemeDB.fallback_font
	for b in ride.bubbles:
		var age: float = ride.t - float(b.t0)
		var sp := P(float(b.x), float(b.d), float(b.h) + 0.4)
		var px := 20 if not portrait else 22
		var msg := String(b.text)
		var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var pop := minf(1.0, age * 10.0)
		var box := Rect2(sp + Vector2(-tw / 2.0 - 10.0, -px - 22.0), Vector2(tw + 20.0, px + 14.0))
		box = Rect2(box.get_center() - box.size * pop / 2.0, box.size * pop)
		var a := clampf(1.6 - age, 0.0, 1.0) * 2.0
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-6, -10), sp + Vector2(6, -10), sp + Vector2(0, 2)]), Color(1, 1, 1, minf(a, 1.0)))
		draw_rect(box, Color(1, 1, 1, minf(a, 1.0)))
		draw_rect(box, Color(0.1, 0.1, 0.1, minf(a, 1.0)), false, 2.0)
		if pop >= 1.0:
			draw_string(font, box.position + Vector2(10, px + 3), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.1, 0.1, 0.1, minf(a, 1.0)))


func _rain() -> void:
	var t: float = ride.t
	for i in 140:
		var hs := absi(hash(i * 7919))
		var rx := fmod(float(hs % 2000) + t * 160.0, _size.x + 100.0) - 50.0
		var ry := fmod(float((hs >> 11) % 2000) + t * 900.0, _size.y + 60.0) - 30.0
		draw_line(Vector2(rx, ry), Vector2(rx - 6.0, ry + 22.0), Color(0.8, 0.85, 0.95, 0.45), 1.5)
	draw_rect(Rect2(Vector2.ZERO, _size), Color(0.2, 0.25, 0.35, 0.12))
