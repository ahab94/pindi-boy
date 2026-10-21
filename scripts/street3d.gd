extends Node3D
## The street in 3D: road, kerbs, footpaths, the nala, shop fronts with
## stocked shelves and signboards, balconies, water tanks, poles with their
## tangle of wires, and neem trees. Built once per ride from the same seeded
## data the 2D view used (world.gd), in 60 m chunks so each chunk is a few
## merged meshes (few draw calls) that the camera culls as a whole.
##
## Axes: X along the road, Y up, Z toward the camera (road depth d -> z = -d).

const World := preload("res://scripts/world.gd")
const MB := preload("res://scripts/mesh_builder.gd")
const View2D := preload("res://scripts/view.gd")

const CHUNK := 60.0
const UV := 0.25              # texture repeats every 4 m

var ride
var tint := Color(1, 1, 1)
var _mat_col: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_road: StandardMaterial3D
var _mat_pave: StandardMaterial3D
var _mat_glass: StandardMaterial3D
static var _tex := {}


func build(r, light_tint: Color) -> void:
	ride = r
	tint = light_tint
	for c in get_children():
		c.queue_free()
	if _tex.is_empty():
		_tex.asphalt = View2D._make_texture("asphalt", 11)
		_tex.paving = View2D._make_texture("paving", 23)
		_tex.plaster = View2D._make_texture("plaster", 37)
	_mat_col = MB.mat(0.85)
	_mat_wall = MB.mat(0.95, _tex.plaster)
	_mat_road = MB.mat(0.9, _tex.asphalt)
	_mat_pave = MB.mat(0.95, _tex.paving)
	_mat_glass = MB.mat(0.15)
	_mat_glass.metallic = 0.3
	var length: float = ride.length
	var x := -80.0
	while x < length + 160.0:
		_chunk(x, x + CHUNK)
		x += CHUNK


func _c(col: Color) -> Color:
	return Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, col.a)


func _chunk(x0: float, x1: float) -> void:
	var col := MB.new()
	var wall := MB.new()
	var road := MB.new()
	var pave := MB.new()
	var glass := MB.new()
	_ground(x0, x1, col, road, pave)
	for b in ride.buildings:
		var bx: float = b.x0
		if bx >= x0 and bx < x1:
			_building(b, col, wall, glass)
	for pl in ride.poles:
		if float(pl.x) >= x0 and float(pl.x) < x1:
			_pole(pl, col)
	for tr in ride.trees:
		if float(tr.x) >= x0 and float(tr.x) < x1:
			_tree(tr, col)
	var fx: float = ride.length
	if fx >= x0 and fx < x1:
		_finish(fx, col)
	var node := Node3D.new()
	add_child(node)
	for pair in [[col, _mat_col], [wall, _mat_wall], [road, _mat_road], [pave, _mat_pave], [glass, _mat_glass]]:
		var mesh: ArrayMesh = (pair[0] as MB).commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = pair[1]
		node.add_child(mi)
	for b in ride.buildings:
		var bx: float = b.x0
		if bx >= x0 and bx < x1:
			_sign_label(b, node)


func _ground(x0: float, x1: float, col: MB, road: MB, pave: MB) -> void:
	var tar := _c(Color(0.32, 0.31, 0.31) if not ride.level.get("rain", false) else Color(0.24, 0.25, 0.28))
	road.quad(Vector3(x0, 0, 0), Vector3(x1, 0, 0), Vector3(x1, 0, -World.ROAD_W), Vector3(x0, 0, -World.ROAD_W), tar, UV)
	var stone := _c(Color(0.72, 0.67, 0.6))
	# Far footpath (raised), its kerb face, the near footpath, the nala and
	# the pavement beyond it.
	pave.box(Vector3(x0, 0, -World.ROAD_W), Vector3(x1, 0.2, -World.FAR_WALK - 7.0), stone, UV, 1 | 4)
	pave.box(Vector3(x0, 0, 0), Vector3(x1, 0.2, -World.NEAR_WALK), stone, UV, 2 | 4)
	col.box(Vector3(x0, -0.3, -World.NEAR_WALK), Vector3(x1, 0.02, -World.NEAR_WALK + 0.8), _c(Color(0.18, 0.24, 0.18)), 0.0, 4)
	pave.box(Vector3(x0, 0, -World.NEAR_WALK + 0.8), Vector3(x1, 0.2, 14.0), _c(Color(0.64, 0.6, 0.54)), UV, 4 | 2)
	# Painted kerb: yellow and black, 1.5 m each.
	var k := x0
	var i := int(floor(x0 / 1.5))
	while k < x1:
		var kc := _c(Color(0.98, 0.82, 0.1) if i % 2 == 0 else Color(0.1, 0.1, 0.1))
		col.box(Vector3(k, 0.0, -World.ROAD_W + 0.02), Vector3(k + 1.5, 0.2, -World.ROAD_W - 0.18), kc, 0.0, 1 | 4)
		k += 1.5
		i += 1
	col.box(Vector3(x0, 0.0, 0.0), Vector3(x1, 0.21, -0.14), _c(Color(0.95, 0.95, 0.92)), 0.0, 2 | 4)
	# Lane dashes and wheel-worn strips.
	var dx := floorf(x0 / 6.0) * 6.0
	while dx < x1:
		for ld in [3.0, 6.0]:
			col.box(Vector3(dx, 0.0, -ld + 0.07), Vector3(dx + 3.0, 0.012, -ld - 0.07), _c(Color(0.93, 0.93, 0.88)), 0.0, 4)
		dx += 6.0
	# Manholes and patches, seeded by position like the 2D view.
	for kk in range(int(floor(x0 / 23.0)), int(x1 / 23.0) + 1):
		var hs := absi(hash(kk * 53 + 11))
		var mx := kk * 23.0 + (hs % 100) / 10.0
		var md := 0.8 + ((hs >> 6) % 75) / 10.0
		if mx < x0 or mx > x1:
			continue
		if hs % 4 == 0:
			col.cylinder(Vector3(mx, 0.0, -md), Vector3(mx, 0.015, -md), 0.42, _c(Color(0.28, 0.28, 0.3)), 14)
		elif hs % 4 == 1:
			col.box(Vector3(mx, 0.0, -md), Vector3(mx + 2.2, 0.008, -md - 1.2), _c(Color(0.32, 0.32, 0.35)), 0.0, 4)


func _building(b: Dictionary, col: MB, wall: MB, glass: MB) -> void:
	var x0: float = b.x0
	var x1: float = b.x1
	var w := x1 - x0
	var zf: float = -(World.FAR_WALK + float(b.setback))
	var zb := zf - 7.0
	var bh: float = b.h
	var wc: Color = _c(b.color)
	# Walls: plaster texture tinted by the wall colour, grimier at the bottom.
	wall.box(Vector3(x0, 0, zf), Vector3(x1, bh, zb), wc, UV, 1 | 16 | 32)
	col.box(Vector3(x0, bh - 0.05, zf), Vector3(x1, bh, zb), _c(Color(0.62, 0.6, 0.58)), 0.0, 4)
	# Parapet with a drip edge.
	col.box(Vector3(x0 - 0.05, bh, zf + 0.08), Vector3(x1 + 0.05, bh + 0.45, zf - 0.15), wc.darkened(0.12))
	col.box(Vector3(x0 - 0.05, bh - 0.12, zf + 0.12), Vector3(x1 + 0.05, bh, zf - 0.02), wc.darkened(0.3))
	var seed: int = b.seed
	# Ground floor: an open shop or a shutter.
	var zs := zf + 0.02
	if b.shutter:
		col.box(Vector3(x0 + 0.3, 0.2, zs), Vector3(x1 - 0.3, 2.55, zs + 0.04), _c(Color(0.62, 0.64, 0.66)))
		for i in 10:
			var y := 0.35 + i * 0.22
			col.box(Vector3(x0 + 0.3, y, zs + 0.04), Vector3(x1 - 0.3, y + 0.04, zs + 0.06), _c(Color(0.5, 0.52, 0.54)))
		col.box(Vector3(x0 + 0.3, 2.5, zs), Vector3(x1 - 0.3, 2.68, zs + 0.14), _c(Color(0.45, 0.46, 0.48)))
	else:
		_shop(x0, x1, zs, seed, col)
	# The signboard (its text is a Label3D, see _sign_label).
	var sc: Color = _c(b.sign_color)
	col.box(Vector3(x0 + 0.15, 2.7, zf + 0.02), Vector3(x1 - 0.15, 3.55, zf + 0.14), sc)
	col.box(Vector3(x0 + 0.15, 3.5, zf + 0.02), Vector3(x1 - 0.15, 3.55, zf + 0.16), sc.lightened(0.3))
	# Upper floors: windows with frames and grills.
	var evening := String(ride.level.sky) in ["dusk", "evening"]
	for f in range(1, int(b.floors)):
		var fy := 3.9 + (f - 1) * 3.0
		var n := maxi(1, int(w / 2.4))
		for i in n:
			var wx := x0 + (w - n * 2.4) / 2.0 + i * 2.4 + 0.6
			col.box(Vector3(wx - 0.1, fy - 0.1, zf + 0.0), Vector3(wx + 1.3, fy + 1.5, zf + 0.06), wc.darkened(0.3))
			var lit := evening and (hash(seed + f * 7 + i) % 3 == 0)
			if lit:
				col.box(Vector3(wx, fy, zf + 0.06), Vector3(wx + 1.2, fy + 1.4, zf + 0.07), Color(1.4, 1.1, 0.6))
			else:
				glass.box(Vector3(wx, fy, zf + 0.06), Vector3(wx + 1.2, fy + 1.4, zf + 0.07), _c(Color(0.25, 0.35, 0.45)))
			for g in 4:
				var gx := wx + 0.24 * (g + 1)
				col.box(Vector3(gx - 0.015, fy, zf + 0.08), Vector3(gx + 0.015, fy + 1.4, zf + 0.11), _c(Color(0.18, 0.18, 0.2)))
			col.box(Vector3(wx - 0.15, fy - 0.16, zf + 0.0), Vector3(wx + 1.35, fy - 0.1, zf + 0.2), wc.darkened(0.15))
		if b.ac and f == 1:
			col.box(Vector3(x1 - 1.3, fy + 1.6, zf), Vector3(x1 - 0.4, fy + 2.15, zf + 0.35), _c(Color(0.9, 0.9, 0.88)))
			col.cylinder(Vector3(x1 - 0.85, fy + 1.87, zf + 0.35), Vector3(x1 - 0.85, fy + 1.87, zf + 0.37), 0.18, _c(Color(0.5, 0.5, 0.52)), 12)
	if b.balcony:
		col.box(Vector3(x0 + 0.8, 3.75, zf), Vector3(x1 - 0.8, 3.9, zf + 0.9), wc.darkened(0.08))
		var rail := _c(Color(0.22, 0.22, 0.24))
		col.box(Vector3(x0 + 0.8, 4.7, zf + 0.86), Vector3(x1 - 0.8, 4.76, zf + 0.92), rail)
		var bars := int((w - 1.6) / 0.25)
		for i in bars + 1:
			var rx := x0 + 0.8 + i * 0.25
			col.box(Vector3(rx - 0.015, 3.9, zf + 0.87), Vector3(rx + 0.015, 4.7, zf + 0.9), rail)
		for i in 3:
			var cx := x0 + 1.2 + i * 0.9
			if cx < x1 - 1.0:
				col.box(Vector3(cx, 4.8, zf + 0.5), Vector3(cx + 0.6, 5.45, zf + 0.52),
					_c(Color.from_hsv(float(i) / 3.0 + float(seed % 10) / 10.0, 0.5, 0.95)))
	if b.tank:
		var tx := x0 + w * 0.3
		col.cylinder(Vector3(tx, bh, zf - 2.5), Vector3(tx, bh + 1.4, zf - 2.5), 0.65, _c(Color(0.1, 0.1, 0.11)), 16)
	if b.dish:
		col.cylinder(Vector3(x0 + w * 0.75, bh, zf - 1.5), Vector3(x0 + w * 0.75, bh + 0.8, zf - 1.5), 0.04, _c(Color(0.5, 0.5, 0.5)), 6)
		col.sphere(Vector3(x0 + w * 0.75, bh + 1.0, zf - 1.4), Vector3(0.45, 0.45, 0.12), _c(Color(0.88, 0.88, 0.88)), 5, 12)


## An open shop: dark inside, three shelves of goods, crisp packets hanging
## at the front, the counter and the owner behind it, and a striped awning.
func _shop(x0: float, x1: float, z: float, seed: int, col: MB) -> void:
	var w := x1 - x0
	col.box(Vector3(x0 + 0.3, 0.2, z - 0.01), Vector3(x1 - 0.3, 2.55, z), _c(Color(0.12, 0.09, 0.08)))
	var wood := _c(Color(0.45, 0.3, 0.18))
	for row in 3:
		var sy := 0.95 + row * 0.5
		col.box(Vector3(x0 + 0.4, sy - 0.04, z), Vector3(x1 - 0.4, sy, z + 0.35), wood)
		var xx := x0 + 0.45
		var k := 0
		while xx < x1 - 0.6:
			var hs := absi(hash(seed + row * 101 + k))
			var gc := _c(Color.from_hsv(float(hs % 97) / 97.0, 0.6, 0.9))
			match hs % 4:
				0:
					col.cylinder(Vector3(xx + 0.05, sy, z + 0.15), Vector3(xx + 0.05, sy + 0.3, z + 0.15), 0.045, gc, 6)
					col.cylinder(Vector3(xx + 0.05, sy + 0.3, z + 0.15), Vector3(xx + 0.05, sy + 0.38, z + 0.15), 0.02, gc.darkened(0.4), 6)
					xx += 0.14
				1:
					col.box(Vector3(xx, sy, z + 0.05), Vector3(xx + 0.28, sy + 0.3, z + 0.3), gc)
					xx += 0.31
				2:
					col.cylinder(Vector3(xx + 0.09, sy, z + 0.15), Vector3(xx + 0.09, sy + 0.26, z + 0.15), 0.09, gc, 8)
					xx += 0.21
				_:
					for q in 3:
						col.box(Vector3(xx, sy + q * 0.1, z + 0.05), Vector3(xx + 0.24, sy + q * 0.1 + 0.08, z + 0.3), gc.lightened(q * 0.1))
					xx += 0.27
			k += 1
	for i in int(w / 1.3):
		var hx := x0 + 0.6 + i * 1.3
		var hs2 := absi(hash(seed * 7 + i))
		var pc := _c(Color.from_hsv(float(hs2 % 100) / 100.0, 0.75, 0.95))
		for q in 5:
			col.box(Vector3(hx, 2.2 - q * 0.19, z + 0.5), Vector3(hx + 0.18, 2.36 - q * 0.19, z + 0.52), pc if q % 2 == 0 else pc.lightened(0.25))
	var ox := x0 + w * 0.5
	col.box(Vector3(ox - 0.9, 0.2, z + 0.4), Vector3(ox + 0.9, 0.9, z + 1.0), wood.darkened(0.1))
	col.box(Vector3(ox - 0.95, 0.9, z + 0.38), Vector3(ox + 0.95, 0.96, z + 1.05), wood.lightened(0.15))
	col.box(Vector3(ox - 0.24, 0.96, z + 0.1), Vector3(ox + 0.24, 1.4, z + 0.32), _c(Color(0.92, 0.92, 0.88)))
	col.sphere(Vector3(ox, 1.58, z + 0.22), Vector3(0.16, 0.18, 0.16), _c(Color(0.72, 0.5, 0.34)))
	col.box(Vector3(ox - 0.08, 1.48, z + 0.37), Vector3(ox + 0.08, 1.52, z + 0.39), _c(Color(0.15, 0.1, 0.08)))
	# Striped awning, sloping out over the footpath.
	for i in int(w / 0.5):
		var ax := x0 + 0.2 + i * 0.5
		var ac := _c(Color(0.85, 0.18, 0.18) if i % 2 == 0 else Color(0.97, 0.95, 0.9))
		col.quad(Vector3(ax, 2.62, z + 0.0), Vector3(ax + 0.5, 2.62, z), Vector3(ax + 0.5, 2.3, z + 1.1), Vector3(ax, 2.3, z + 1.1), ac)


func _sign_label(b: Dictionary, parent: Node3D) -> void:
	var l := Label3D.new()
	l.text = String(b.sign)
	var w: float = float(b.x1) - float(b.x0)
	l.font_size = 96
	l.outline_size = 0
	l.pixel_size = minf(0.0055, (w - 0.6) / (l.text.length() * 58.0))
	l.modulate = Color(1, 1, 1) if (b.sign_color as Color).get_luminance() < 0.55 else Color(0.1, 0.1, 0.1)
	l.position = Vector3((float(b.x0) + float(b.x1)) / 2.0, 3.12, -(World.FAR_WALK + float(b.setback)) + 0.16)
	l.shaded = false
	l.double_sided = false
	parent.add_child(l)


func _pole(pl: Dictionary, col: MB) -> void:
	var px: float = pl.x
	var ph: float = pl.h
	var z := -10.0
	var concrete := _c(Color(0.6, 0.6, 0.58))
	col.cylinder(Vector3(px, 0.2, z), Vector3(px + float(pl.lean) * ph, ph, z), 0.12, concrete, 8, true, 0.08)
	var top := Vector3(px + float(pl.lean) * ph, ph, z)
	col.box(top + Vector3(-0.7, -0.08, -0.06), top + Vector3(0.7, 0.04, 0.06), _c(Color(0.35, 0.3, 0.25)))
	if hash(int(px)) % 3 == 0:
		col.box(top + Vector3(-0.35, -2.5, 0.1), top + Vector3(0.35, -1.5, 0.5), _c(Color(0.45, 0.48, 0.45)))
	# Wires to the next pole and off to the houses.
	var idx: int = ride.poles.find(pl)
	var wire := Color(0.05, 0.05, 0.05)
	if idx >= 0 and idx + 1 < ride.poles.size():
		var nx: Dictionary = ride.poles[idx + 1]
		var ntop := Vector3(float(nx.x) + float(nx.lean) * float(nx.h), float(nx.h), z)
		for k in 4:
			var off := Vector3(-0.6 + k * 0.4, -0.05 * k, 0.0)
			_wire(top + off, ntop + off, 0.8 + k * 0.15, wire, col)
	for k in 3:
		_wire(top, Vector3(px + 3.0 + k * 4.0, 4.5 + k * 0.8, -World.FAR_WALK), 0.4, wire, col)


func _wire(a: Vector3, b: Vector3, sag: float, c: Color, col: MB) -> void:
	var prev := a
	for i in range(1, 9):
		var f := i / 8.0
		var p := a.lerp(b, f) - Vector3(0, sag * 4.0 * f * (1.0 - f), 0)
		col.cylinder(prev, p, 0.012, c, 3, false)
		prev = p


func _tree(tr: Dictionary, col: MB) -> void:
	var tx: float = tr.x
	var th: float = tr.h
	var r: float = tr.r
	var seed: int = tr.seed
	var z := -10.4
	var bark := _c(Color(0.4, 0.29, 0.2))
	col.cylinder(Vector3(tx, 0.2, z), Vector3(tx + 0.15, th * 0.6, z), 0.2, bark, 8, false, 0.14)
	col.cylinder(Vector3(tx + 0.15, th * 0.5, z), Vector3(tx - 0.7, th * 0.78, z + 0.2), 0.09, bark, 6, false)
	col.cylinder(Vector3(tx + 0.15, th * 0.5, z), Vector3(tx + 0.8, th * 0.82, z - 0.2), 0.08, bark, 6, false)
	var greens := [Color(0.2, 0.42, 0.18), Color(0.27, 0.5, 0.22), Color(0.34, 0.58, 0.26)]
	for i in 14:
		var hs := absi(hash(seed * 31 + i))
		var a := float(i) / 14.0 * TAU
		var c := Vector3(tx + cos(a) * r * 0.6, th + sin(a * 2.0) * 0.4 + (hs % 50) / 100.0, z + sin(a) * r * 0.5)
		var rr := r * (0.45 + float(hs % 30) / 100.0)
		col.sphere(c, Vector3(rr, rr * 0.8, rr), _c(greens[i % 3]), 5, 8)


func _finish(fx: float, col: MB) -> void:
	for i in 9:
		var c := Color(1, 1, 1) if i % 2 == 0 else Color(0.1, 0.1, 0.1)
		col.box(Vector3(fx, 0.0, -i), Vector3(fx + 0.6, 0.015, -i - 1.0), c, 0.0, 4)
	var wood := _c(Color(0.4, 0.3, 0.2))
	col.cylinder(Vector3(fx - 0.3, 0.2, -World.FAR_WALK + 0.3), Vector3(fx - 0.3, 3.6, -World.FAR_WALK + 0.3), 0.06, wood)
	col.cylinder(Vector3(fx + 0.9, 0.2, -World.FAR_WALK + 0.3), Vector3(fx + 0.9, 3.6, -World.FAR_WALK + 0.3), 0.06, wood)
	col.box(Vector3(fx - 0.6, 3.0, -World.FAR_WALK + 0.2), Vector3(fx + 1.2, 3.8, -World.FAR_WALK + 0.4), _c(Color(0.1, 0.5, 0.25)))
