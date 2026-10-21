extends RefCounted
## 3D models for everything on the road, built from parts with
## mesh_builder.gd. Each function returns a mesh in the thing's own frame:
## origin on the ground at its centre, facing +X, Z across the road
## (positive toward the camera). Meshes are cached and shared, so ten
## rickshaws cost one mesh.

const MB := preload("res://scripts/mesh_builder.gd")

const CHROME := Color(0.82, 0.84, 0.88)
const TYRE := Color(0.08, 0.08, 0.09)
const RICKSHAW_BODY := [Vector2(-1.32, 0.32), Vector2(0.95, 0.32), Vector2(1.3, 0.36), Vector2(1.42, 0.55),
	Vector2(1.36, 0.82), Vector2(1.12, 1.02), Vector2(0.92, 1.05), Vector2(0.86, 0.9), Vector2(-1.25, 0.9),
	Vector2(-1.36, 0.75)]
const RICKSHAW_HOOD := [Vector2(1.06, 1.1), Vector2(0.92, 1.9), Vector2(0.62, 2.04), Vector2(-0.2, 2.08),
	Vector2(-0.9, 2.04), Vector2(-1.28, 1.9), Vector2(-1.4, 1.4), Vector2(-1.38, 0.9), Vector2(-1.2, 0.9),
	Vector2(-1.2, 1.62), Vector2(-0.95, 1.86), Vector2(0.6, 1.86), Vector2(0.82, 1.8), Vector2(0.9, 1.08)]

static var _cache := {}


static func get_mesh(kind: String, look: int) -> ArrayMesh:
	var key := "%s/%d" % [kind, look % 3]
	if not _cache.has(key):
		_cache[key] = _make(kind, look % 3)
	return _cache[key]


static func _make(kind: String, look: int) -> ArrayMesh:
	var mb := MB.new()
	match kind:
		"rickshaw", "wrongway":
			_rickshaw(mb, look)
		"wagon":
			_wagon(mb, look)
		"bus":
			_bus(mb, look)
		"cart":
			_cart(mb, look, false)
		"eggs":
			_cart(mb, look, true)
		"ramp":
			_ramp(mb)
		"breaker":
			_breaker(mb)
		"pothole":
			mb.cylinder(Vector3(0, -0.02, 0), Vector3(0, 0.012, 0), 0.6, Color(0.22, 0.21, 0.2), 16)
			mb.cylinder(Vector3(0, -0.01, 0), Vector3(0, 0.014, 0), 0.45, Color(0.07, 0.06, 0.06), 16)
		"goat":
			_goat(mb, look)
		"pigeon":
			mb.sphere(Vector3(0, 0.12, 0), Vector3(0.14, 0.08, 0.07), Color(0.55, 0.57, 0.62), 5, 8)
			mb.sphere(Vector3(0.13, 0.2, 0), Vector3(0.05, 0.05, 0.05), Color(0.45, 0.47, 0.52), 4, 6)
			mb.box(Vector3(0.17, 0.19, -0.01), Vector3(0.21, 0.2, 0.01), Color(0.85, 0.55, 0.4))
			mb.box(Vector3(-0.2, 0.1, -0.04), Vector3(-0.1, 0.13, 0.04), Color(0.4, 0.42, 0.46))
		"wing":
			mb.box(Vector3(-0.08, 0.0, 0.0), Vector3(0.08, 0.01, 0.2), Color(0.62, 0.64, 0.7))
		"horse":
			_horse(mb)
		"chappal":
			mb.box(Vector3(-0.15, 0.0, -0.06), Vector3(0.15, 0.025, 0.06), Color(0.45, 0.25, 0.1))
			mb.box(Vector3(0.0, 0.025, -0.06), Vector3(0.04, 0.06, 0.06), Color(0.75, 0.15, 0.1))
	return mb.commit()


static func _rk_half(along: float) -> float:
	return lerpf(1.0, 0.4, clampf((along - 0.7) / 0.72, 0.0, 1.0))


static func _rickshaw(mb: MB, look: int) -> void:
	var body: Color = [Color(0.12, 0.55, 0.3), Color(0.95, 0.72, 0.08), Color(0.15, 0.38, 0.75)][look]
	var hood := Color(0.09, 0.09, 0.1)
	var taper := func(x: float) -> float: return _rk_half(x)
	mb.extrude(RICKSHAW_BODY, 0.0, 0.58, taper, body)
	mb.extrude(RICKSHAW_HOOD, 0.0, 0.6, taper, hood)
	# The roof canvas between the two hood sides (extrude only made the rims).
	for i in range(0, 6):
		var a: Vector2 = RICKSHAW_HOOD[i]
		var b: Vector2 = RICKSHAW_HOOD[i + 1]
		mb.quad(Vector3(a.x, a.y, 0.6 * _rk_half(a.x)), Vector3(b.x, b.y, 0.6 * _rk_half(b.x)),
			Vector3(b.x, b.y, -0.6 * _rk_half(b.x)), Vector3(a.x, a.y, -0.6 * _rk_half(a.x)), hood.lightened(0.08))
	# Cabin floor, the back bench, the windscreen.
	mb.box(Vector3(-1.2, 0.86, -0.55), Vector3(0.86, 0.9, 0.55), body.darkened(0.4))
	mb.box(Vector3(-1.18, 0.9, -0.5), Vector3(-0.45, 1.12, 0.5), Color(0.55, 0.12, 0.15))
	mb.box(Vector3(-1.2, 1.1, -0.5), Vector3(-1.1, 1.45, 0.5), Color(0.45, 0.1, 0.12))
	mb.quad(Vector3(1.02, 1.1, 0.42), Vector3(1.02, 1.1, -0.42), Vector3(0.88, 1.84, -0.48), Vector3(0.88, 1.84, 0.48), Color(0.55, 0.72, 0.82))
	# Handlebar and the driver's seat.
	mb.cylinder(Vector3(0.78, 1.25, -0.25), Vector3(0.78, 1.25, 0.25), 0.02, Color(0.15, 0.15, 0.15), 6)
	mb.box(Vector3(0.15, 0.9, -0.22), Vector3(0.5, 1.05, 0.22), Color(0.15, 0.12, 0.1))
	# Paintwork on both sides: chrome strip, a big painted eye, flowers.
	for side in [1.0, -1.0]:
		var z: float = 0.585 * side
		mb.box(Vector3(-1.25, 0.6, z - 0.01), Vector3(0.9, 0.64, z + 0.01), CHROME)
		mb.cylinder(Vector3(-0.2, 0.75, z), Vector3(-0.2, 0.75, z + 0.012 * side), 0.13, Color(1, 1, 1), 14)
		mb.cylinder(Vector3(-0.2, 0.75, z + 0.012 * side), Vector3(-0.2, 0.75, z + 0.02 * side), 0.055, Color(0.1, 0.3, 0.8), 10)
		for fx in [-0.85, 0.35]:
			for k in 5:
				var a := TAU * k / 5.0
				mb.cylinder(Vector3(fx + cos(a) * 0.05, 0.45 + sin(a) * 0.05, z), Vector3(fx + cos(a) * 0.05, 0.45 + sin(a) * 0.05, z + 0.012 * side), 0.045,
					[Color(1, 0.3, 0.5), Color(1, 1, 1)][int(fx > 0.0)], 8)
		# Tassels along the hood edge.
		for i in 9:
			var tx := -1.15 + i * 0.22
			mb.cylinder(Vector3(tx, 1.86, 0.6 * side), Vector3(tx, 1.74, 0.6 * side), 0.035,
				[Color(1, 0.2, 0.3), Color(1, 0.85, 0.1), Color(0.2, 0.8, 0.4)][i % 3], 5, true, 0.0)
	# Headlight, tail lights.
	mb.cylinder(Vector3(1.38, 0.72, 0.0), Vector3(1.44, 0.72, 0.0), 0.08, CHROME, 12)
	mb.cylinder(Vector3(1.44, 0.72, 0.0), Vector3(1.45, 0.72, 0.0), 0.06, Color(1, 0.96, 0.75), 12)
	for side in [-0.4, 0.4]:
		mb.box(Vector3(-1.38, 0.48, side - 0.05), Vector3(-1.35, 0.56, side + 0.05), Color(1, 0.15, 0.1))
	# Wheels: two at the back, one under the nose.
	for wz in [-0.52, 0.52]:
		_wheel(mb, Vector3(-0.85, 0.22, wz), 0.22, 0.09)
	_wheel(mb, Vector3(0.98, 0.22, 0.0), 0.22, 0.09)


static func _wheel(mb: MB, c: Vector3, r: float, w: float) -> void:
	mb.cylinder(c - Vector3(0, 0, w / 2), c + Vector3(0, 0, w / 2), r, TYRE, 16)
	mb.cylinder(c - Vector3(0, 0, w / 2 + 0.005), c + Vector3(0, 0, w / 2 + 0.005), r * 0.55, Color(0.62, 0.63, 0.66), 12)


static func _wagon(mb: MB, look: int) -> void:
	var white := Color(0.95, 0.95, 0.93) if look != 1 else Color(0.85, 0.9, 0.96)
	var glass := Color(0.2, 0.28, 0.34)
	mb.box(Vector3(-2.2, 0.3, -0.9), Vector3(1.7, 2.0, 0.9), white)
	# Sloped nose and windscreen.
	mb.extrude([Vector2(1.7, 0.3), Vector2(2.25, 0.3), Vector2(2.25, 1.05), Vector2(1.95, 1.75), Vector2(1.7, 2.0)], 0.0, 0.9,
		func(_x): return 1.0, white)
	mb.quad(Vector3(2.26, 1.08, 0.82), Vector3(2.26, 1.08, -0.82), Vector3(1.96, 1.78, -0.82), Vector3(1.96, 1.78, 0.82), glass)
	for side in [1.0, -1.0]:
		var z: float = 0.905 * side
		mb.box(Vector3(-2.0, 1.15, z - 0.005), Vector3(1.6, 1.7, z + 0.005), glass)
		mb.box(Vector3(-2.2, 0.75, z - 0.006), Vector3(2.25, 0.85, z + 0.006), Color(0.85, 0.12, 0.12))
		mb.box(Vector3(0.2, 0.32, z - 0.007), Vector3(0.95, 1.7, z + 0.007), white.darkened(0.08))
		for wx in [-1.5, 1.5]:
			_wheel(mb, Vector3(wx, 0.3, 0.85 * side), 0.3, 0.16)
	mb.box(Vector3(2.24, 0.3, -0.85), Vector3(2.32, 0.45, 0.85), CHROME)
	# Roof rack and luggage: a trunk, a tied bundle, a bicycle wheel.
	mb.box(Vector3(-1.9, 2.0, -0.75), Vector3(1.2, 2.06, 0.75), Color(0.25, 0.25, 0.27))
	mb.box(Vector3(-1.6, 2.06, -0.6), Vector3(-0.3, 2.45, 0.55), Color(0.5, 0.32, 0.18))
	mb.box(Vector3(-0.2, 2.06, -0.5), Vector3(0.9, 2.32, 0.5), Color(0.25, 0.45, 0.7))
	mb.cylinder(Vector3(0.95, 2.4, -0.5), Vector3(0.95, 2.4, -0.45), 0.3, Color(0.15, 0.15, 0.15), 14, false)


static func _bus(mb: MB, look: int) -> void:
	var base := Color(0.98, 0.78, 0.1) if look != 1 else Color(0.95, 0.38, 0.15)
	mb.box(Vector3(-5.25, 0.45, -1.2), Vector3(5.25, 3.3, 1.2), base)
	for side in [1.0, -1.0]:
		var z: float = 1.205 * side
		mb.box(Vector3(-5.25, 0.45, z - 0.005), Vector3(5.25, 0.95, z + 0.005), Color(0.1, 0.45, 0.8))
		mb.box(Vector3(-5.25, 1.55, z - 0.006), Vector3(5.25, 1.75, z + 0.006), Color(0.85, 0.1, 0.25))
		mb.box(Vector3(-5.25, 2.95, z - 0.006), Vector3(5.25, 3.1, z + 0.006), Color(0.1, 0.6, 0.35))
		for i in 14:
			var fx := -4.9 + i * 0.75
			for k in 5:
				var a := TAU * k / 5.0
				mb.cylinder(Vector3(fx + cos(a) * 0.08, 0.7 + sin(a) * 0.08, z), Vector3(fx + cos(a) * 0.08, 0.7 + sin(a) * 0.08, z + 0.012 * side),
					0.07, [Color(1, 0.3, 0.5), Color(1, 1, 1), Color(0.3, 0.9, 0.4)][i % 3], 8)
		for i in 8:
			var wx := -4.6 + i * 1.12
			mb.box(Vector3(wx, 1.85, z - 0.008), Vector3(wx + 0.85, 2.85, z + 0.008), Color(0.2, 0.3, 0.36))
			mb.sphere(Vector3(wx + 0.42, 2.25, z * 0.9), Vector3(0.14, 0.17, 0.14), [Color(0.78, 0.55, 0.38), Color(0.62, 0.42, 0.28)][(i + look) % 2], 4, 8)
		for i in 12:
			var cx := -5.0 + i * 0.9
			mb.cylinder(Vector3(cx, 0.45, z), Vector3(cx, 0.18, z), 0.012, CHROME, 4, false)
		for wx in [-3.6, 3.6]:
			_wheel(mb, Vector3(wx, 0.45, 1.12 * side), 0.45, 0.25)
	mb.box(Vector3(5.25, 1.6, -1.1), Vector3(5.27, 2.85, 1.1), Color(0.3, 0.45, 0.55))
	mb.box(Vector3(5.25, 0.45, -1.2), Vector3(5.4, 0.7, 1.2), CHROME)
	# Roof rack with sacks and a man sitting on top.
	mb.box(Vector3(-4.5, 3.3, -1.0), Vector3(3.0, 3.38, 1.0), Color(0.3, 0.3, 0.3))
	for i in 5:
		mb.sphere(Vector3(-4.0 + i * 1.2, 3.62, 0.2 - (i % 2) * 0.4), Vector3(0.5, 0.3, 0.4), Color(0.75, 0.68, 0.5), 4, 8)


static func _cart(mb: MB, look: int, burger: bool) -> void:
	var wood := Color(0.55, 0.36, 0.2)
	mb.box(Vector3(-1.1, 0.6, -0.62), Vector3(1.1, 0.85, 0.62), wood)
	mb.box(Vector3(-1.1, 0.85, -0.62), Vector3(1.1, 0.95, -0.56), wood.darkened(0.2))
	mb.box(Vector3(-1.1, 0.85, 0.56), Vector3(1.1, 0.95, 0.62), wood.darkened(0.2))
	for side in [-1.0, 1.0]:
		_wheel(mb, Vector3(0.0, 0.36, 0.66 * side), 0.36, 0.05)
		mb.cylinder(Vector3(-1.1, 0.75, 0.5 * side), Vector3(-1.65, 0.95, 0.5 * side), 0.03, wood.darkened(0.3), 6)
		mb.cylinder(Vector3(0.95, 0.6, 0.5 * side), Vector3(0.95, 0.0, 0.5 * side), 0.03, wood.darkened(0.3), 6)
	if burger:
		# Glass case of buns, the hot tawa with eggs, bottles, gas cylinder,
		# and the sign on two poles.
		# The glass case: just its frame and a top, so the buns show.
		for cx in [-1.05, 0.1]:
			for cz in [-0.5, 0.5]:
				mb.box(Vector3(cx - 0.02, 0.95, cz - 0.02), Vector3(cx + 0.02, 1.42, cz + 0.02), Color(0.85, 0.85, 0.88))
		mb.box(Vector3(-1.07, 1.4, -0.52), Vector3(0.12, 1.43, 0.52), Color(0.8, 0.9, 0.95))
		for i in 3:
			for j in 2:
				mb.sphere(Vector3(-0.85 + i * 0.33, 1.05 + j * 0.16, 0.1 - j * 0.2), Vector3(0.14, 0.07, 0.14), Color(0.92, 0.66, 0.28), 4, 8)
		mb.cylinder(Vector3(0.6, 0.95, 0.0), Vector3(0.6, 1.0, 0.0), 0.42, Color(0.12, 0.12, 0.12), 18)
		for k in 3:
			var ex := 0.45 + k * 0.17
			mb.cylinder(Vector3(ex, 1.0, 0.1 - k * 0.1), Vector3(ex, 1.012, 0.1 - k * 0.1), 0.1, Color(0.98, 0.97, 0.92), 12)
			mb.sphere(Vector3(ex, 1.02, 0.1 - k * 0.1), Vector3(0.035, 0.02, 0.035), Color(1, 0.72, 0.1), 3, 6)
		mb.cylinder(Vector3(1.0, 0.95, 0.4), Vector3(1.0, 1.18, 0.4), 0.035, Color(0.85, 0.1, 0.1), 8)
		mb.cylinder(Vector3(1.0, 0.95, 0.3), Vector3(1.0, 1.15, 0.3), 0.035, Color(0.2, 0.6, 0.25), 8)
		mb.cylinder(Vector3(-0.3, 0.05, 0.0), Vector3(-0.3, 0.55, 0.0), 0.16, Color(0.2, 0.35, 0.75), 12)
		for side in [-1.0, 1.0]:
			mb.cylinder(Vector3(side * 1.0, 0.95, -0.55), Vector3(side * 1.0, 1.9, -0.55), 0.025, wood.darkened(0.3), 6)
		mb.box(Vector3(-1.1, 1.6, -0.6), Vector3(1.1, 1.92, -0.52), Color(0.98, 0.85, 0.15))
	else:
		var fruit: Color = [Color(1, 0.55, 0.05), Color(0.95, 0.85, 0.15), Color(0.85, 0.1, 0.15)][look]
		for row in 3:
			for i in 7 - row * 2:
				for j in 4 - row:
					mb.sphere(Vector3(-0.8 + row * 0.25 + i * 0.25, 0.98 + row * 0.18, -0.38 + row * 0.12 + j * 0.25),
						Vector3(0.12, 0.12, 0.12), fruit.lightened(0.05 * ((i + j) % 3)), 4, 8)


static func _ramp(mb: MB) -> void:
	# A plank leaning on a pile of bricks.
	mb.box(Vector3(0.7, 0.0, -0.75), Vector3(1.4, 0.9, 0.75), Color(0.72, 0.3, 0.2))
	for row in 4:
		mb.box(Vector3(0.69, 0.22 * (row + 1) - 0.015, -0.76), Vector3(1.41, 0.22 * (row + 1), 0.76), Color(0.88, 0.82, 0.72))
	mb.extrude([Vector2(-1.4, 0.0), Vector2(1.4, 0.95), Vector2(1.4, 1.02), Vector2(-1.45, 0.05)], 0.0, 0.85, func(_x): return 1.0,
		Color(0.78, 0.6, 0.35), Color(0.6, 0.45, 0.25))


static func _breaker(mb: MB) -> void:
	# A hump across the whole road, painted yellow and black.
	for i in 10:
		var z0 := -i * 0.9
		var c := Color(0.95, 0.8, 0.1) if i % 2 == 0 else Color(0.12, 0.12, 0.12)
		mb.extrude([Vector2(-0.4, 0.0), Vector2(0.4, 0.0), Vector2(0.15, 0.16), Vector2(-0.15, 0.16)], z0 - 0.45, 0.45, func(_x): return 1.0, c)


static func _goat(mb: MB, look: int) -> void:
	var col: Color = [Color(0.95, 0.94, 0.9), Color(0.2, 0.18, 0.16), Color(0.6, 0.42, 0.25)][look]
	mb.sphere(Vector3(0, 0.55, 0), Vector3(0.42, 0.2, 0.17), col, 5, 10)
	mb.cylinder(Vector3(0.3, 0.6, 0), Vector3(0.48, 0.85, 0), 0.08, col, 8)
	mb.sphere(Vector3(0.58, 0.85, 0), Vector3(0.13, 0.08, 0.07), col, 4, 8)
	for side in [-0.05, 0.05]:
		mb.cylinder(Vector3(0.52, 0.92, side), Vector3(0.45, 1.02, side * 1.8), 0.015, Color(0.5, 0.45, 0.4), 4, false)
		mb.box(Vector3(0.48, 0.8, side * 2.5 - 0.01), Vector3(0.53, 0.86, side * 2.5 + 0.01), col.darkened(0.2))
	for lx in [-0.28, 0.28]:
		for lz in [-0.1, 0.1]:
			mb.cylinder(Vector3(lx, 0.45, lz), Vector3(lx, 0.0, lz), 0.03, col.darkened(0.25), 5)
	mb.cylinder(Vector3(-0.42, 0.6, 0), Vector3(-0.5, 0.72, 0), 0.03, col, 4)


static func _horse(mb: MB) -> void:
	var white := Color(0.95, 0.95, 0.93)
	mb.sphere(Vector3(0, 1.2, 0), Vector3(0.75, 0.32, 0.26), white, 6, 12)
	mb.cylinder(Vector3(0.55, 1.3, 0), Vector3(0.85, 1.8, 0), 0.14, white, 10)
	mb.sphere(Vector3(0.98, 1.78, 0), Vector3(0.24, 0.12, 0.11), white, 5, 10)
	for lx in [-0.5, 0.5]:
		for lz in [-0.15, 0.15]:
			mb.cylinder(Vector3(lx, 1.0, lz), Vector3(lx, 0.0, lz), 0.05, white.darkened(0.1), 6)
	# Wedding finery: a red cloth with gold dots, a plume.
	mb.box(Vector3(-0.5, 1.05, -0.28), Vector3(0.45, 1.45, 0.28), Color(0.8, 0.1, 0.2))
	for i in 6:
		mb.sphere(Vector3(-0.45 + i * 0.18, 1.06, 0.285), Vector3(0.03, 0.03, 0.01), Color(1, 0.85, 0.2), 3, 6)
	mb.cylinder(Vector3(0.9, 1.88, 0), Vector3(0.88, 2.2, 0), 0.04, Color(1, 0.3, 0.5), 6, true, 0.0)
