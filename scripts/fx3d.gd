extends MultiMeshInstance3D
## Bits flying about in 3D: dust, sparks, fruit and buns from a crash,
## feathers, water, pataakha smoke and confetti. All of them are instances
## of one small cube in a MultiMesh, so hundreds cost a single draw call.
## Each has a position, velocity, life and colour, updated here every frame.
##
## Godot note: a MultiMesh draws the same mesh many times with a transform
## (and colour) per instance; setting an instance's transform each frame is
## far cheaper than moving hundreds of nodes.

const MAX := 320

var ride
var view
var _bits: Array = []
var _seen := 0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	mm.mesh = cube
	mm.instance_count = MAX
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in MAX:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func reset() -> void:
	_bits.clear()
	_seen = 0


func _spawn(p: Vector3, v: Vector3, life: float, col: Color, size: float, kind := "") -> void:
	if _bits.size() >= MAX:
		_bits.pop_front()
	_bits.append({"p": p, "v": v, "life": life, "max": life, "col": col, "size": size, "kind": kind,
		"spin": Vector3(randf(), randf(), randf()) * 10.0})


func step(delta: float) -> void:
	if ride == null:
		return
	_read_events()
	var mm := multimesh
	var i := 0
	var keep: Array = []
	for b in _bits:
		b.life = float(b.life) - delta
		if float(b.life) <= 0.0:
			continue
		var vel: Vector3 = b.v
		var g := 9.0
		match String(b.kind):
			"smoke":
				g = -1.2
			"feather", "confetti":
				g = 1.6
				vel *= 0.985
		vel.y -= g * delta
		var pos: Vector3 = b.p + vel * delta
		if pos.y < 0.02 and b.kind != "smoke":
			pos.y = 0.02
			vel = Vector3(vel.x * 0.4, -vel.y * 0.25, vel.z * 0.4)
		b.p = pos
		b.v = vel
		keep.append(b)
		if i < MAX:
			var f: float = float(b.life) / float(b.max)
			var s: float = float(b.size) * (1.0 + (1.0 - f) * 2.0 if b.kind == "smoke" else 1.0)
			var spin: Vector3 = b.spin * (float(b.max) - float(b.life))
			var shape := Vector3(s, s, s)
			if b.kind == "feather" or b.kind == "confetti":
				shape = Vector3(s * 1.6, s * 0.2, s)
			elif b.kind == "spark" or b.kind == "drop":
				shape = Vector3(s * 2.5, s * 0.5, s * 0.5)
			mm.set_instance_transform(i, Transform3D(Basis.from_euler(spin).scaled(shape), pos))
			var col: Color = b.col
			col.a = clampf(f * 1.5, 0.0, 1.0)
			mm.set_instance_color(i, col)
			i += 1
	_bits = keep
	for k in range(i, MAX):
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func _read_events() -> void:
	for idx in range(_seen, ride.events.size()):
		var words := String(ride.events[idx][1]).split(" ")
		var x: float = ride.x
		var z: float = -float(ride.d)
		match words[0]:
			"pop":
				view.shake = maxf(view.shake, 4.0)
				for k in 12:
					_spawn(Vector3(x - 0.45, 0.42, z + 0.17), Vector3(randf_range(-4, -1), randf_range(0, 1.5), randf_range(-0.6, 0.6)),
						0.4, Color(1, randf_range(0.4, 0.8), 0.1), 0.05, "spark")
				for k in 8:
					_spawn(Vector3(x - 0.5, 0.45, z + 0.17), Vector3(randf_range(-2, -0.5), randf_range(0.3, 1.0), randf_range(-0.4, 0.4)),
						1.0, Color(0.22, 0.22, 0.25), 0.15, "smoke")
			"crash":
				view.shake = maxf(view.shake, 14.0)
				var cause := words[1] if words.size() > 1 else ""
				for k in 16:
					_spawn(Vector3(x + 0.8, 0.3, z), Vector3(randf_range(-2, 5), randf_range(1, 5), randf_range(-1, 1)),
						0.9, Color(0.7, 0.64, 0.52), 0.12, "dust")
				for k in 10:
					_spawn(Vector3(x + 0.5, 0.1, z), Vector3(randf_range(2, 7), randf_range(0, 2), randf_range(-0.5, 0.5)),
						0.4, Color(1, 0.85, 0.3), 0.04, "spark")
				if cause == "cart":
					for k in 18:
						_spawn(Vector3(x + 1.5, 1.0, z), Vector3(randf_range(-3, 6), randf_range(2, 7), randf_range(-1.5, 1.5)),
							1.8, [Color(1, 0.55, 0.05), Color(0.95, 0.85, 0.15), Color(0.85, 0.1, 0.15)][k % 3], 0.13)
				elif cause == "eggs":
					for k in 20:
						_spawn(Vector3(x + 1.5, 1.0, z), Vector3(randf_range(-3, 6), randf_range(2, 7), randf_range(-1.5, 1.5)),
							1.8, [Color(1, 0.8, 0.1), Color(1, 1, 0.95), Color(0.92, 0.66, 0.28)][k % 3], 0.12)
			"land":
				view.shake = maxf(view.shake, 3.0)
				for k in 10:
					_spawn(Vector3(x + 0.3, 0.05, z), Vector3(randf_range(-3, 1), randf_range(0.2, 1.2), randf_range(-0.8, 0.8)),
						0.7, Color(0.7, 0.64, 0.52), 0.1, "dust")
			"pigeons":
				for k in 14:
					_spawn(Vector3(x + 4.0, 0.4, z), Vector3(randf_range(-2, 2), randf_range(0.5, 2.5), randf_range(-1, 1)),
						2.0, Color(0.88, 0.88, 0.92), 0.06, "feather")
			"splash":
				for k in 20:
					_spawn(Vector3(x + 0.6, 0.1, z), Vector3(randf_range(-2, 3), randf_range(1.5, 4), randf_range(-1.5, 1.5)),
						0.7, Color(0.6, 0.72, 0.88), 0.05, "drop")
			"chappal":
				view.shake = maxf(view.shake, 6.0)
				for k in 10:
					_spawn(Vector3(x + 0.6, 1.8, z), Vector3(randf_range(-2, 2), randf_range(0, 3), randf_range(-1, 1)),
						0.6, Color(1, 0.9, 0.2), 0.06, "spark")
			"bank":
				if words.size() > 1 and int(words[1]) >= 1000:
					for k in 30:
						_spawn(Vector3(x + 0.5, 2.5, z), Vector3(randf_range(-4, 4), randf_range(2, 6), randf_range(-1, 1)),
							1.6, Color.from_hsv(randf(), 0.8, 1.0), 0.07, "confetti")
	_seen = ride.events.size()
