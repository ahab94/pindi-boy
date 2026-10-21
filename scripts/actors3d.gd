extends Node3D
## Everything that moves, in 3D: Shani on his bike, the warden, traffic with
## its drivers and passengers, thelas and their vendors, crossing uncles and
## aunties, goats, pigeons, the baraat, the crowd on the footpath, Ammi and
## her chappals. Nodes are made when a ride starts (never mid-ride) and
## moved to match ride.gd every frame.
##
## People are expensive to animate (skinned meshes), so:
## - Passengers, vendors and the baraat are posed once and baked into plain
##   static meshes ("templates"), then copied.
## - Crossers and Ammi are animated.
## - The crowd shares a small pool of animated people, placed on whichever
##   spectators are near the camera.

const World := preload("res://scripts/world.gd")
const MB := preload("res://scripts/mesh_builder.gd")
const Rider := preload("res://scripts/rider3d.gd")
const Ride := preload("res://scripts/ride.gd")
const Person := preload("res://scripts/person3d.gd")
const V := preload("res://scripts/vehicles3d.gd")

const CROWD_POOL := 9

var ride
var _nodes := {}             # hazard index -> Node3D
var _people := {}            # hazard index -> Person (crossers)
var _bike: Rider
var _warden: Rider
var _pose := ""
var _mat := MB.mat(0.6)
var _puddle_mat: StandardMaterial3D
var _templates := {}         # name -> Node3D (baked, static)
var _waiting: Array = []     # [parent, template name, transform] to fill once baked
var _crowd: Array = []       # pooled animated spectators
var _ammi: Person
var _ledge: MeshInstance3D
var _chappals: Array = []
var _rings: Array = []
var _throws := 0


func build(r) -> void:
	ride = r
	for c in get_children():
		c.queue_free()
	_nodes.clear()
	_people.clear()
	_waiting.clear()
	_crowd.clear()
	_chappals.clear()
	_rings.clear()
	_throws = 0
	_puddle_mat = StandardMaterial3D.new()
	_puddle_mat.albedo_color = Color(0.32, 0.4, 0.5, 0.85)
	_puddle_mat.metallic = 0.6
	_puddle_mat.roughness = 0.05
	_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in ride.hazards.size():
		var o: Dictionary = ride.hazards[i]
		var n := _make_hazard(i, o)
		add_child(n)
		_nodes[i] = n
	_bike = Rider.new()
	_bike.kind = String(ride.level.bike)
	add_child(_bike)
	_pose = ""
	_warden = null
	if not ride.warden.is_empty():
		_warden = Rider.new()
		_warden.kind = "warden"
		_warden.rider_role = "warden"
		add_child(_warden)
	for i in CROWD_POOL:
		var p := Person.new()
		p.role = ["uncle", "aunty", "kid", "oldman", "uncle", "aunty", "uncle", "kid", "aunty"][i]
		p.look = i * 3 + 1
		p.face_dir = 0.0
		p.visible = false
		add_child(p)
		_crowd.append(p)
	_ammi = null
	if ride.level.get("chappals", false):
		_ledge = MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(2.4, 0.15, 0.6)
		_ledge.mesh = lb
		_ledge.material_override = Person._mat(Color(0.85, 0.8, 0.72), 0.9)
		add_child(_ledge)
		_ammi = Person.new()
		_ammi.role = "ammi"
		_ammi.face_dir = 0.0
		add_child(_ammi)
		var cm := V.get_mesh("chappal", 0)
		for i in 6:
			var c := MeshInstance3D.new()
			c.mesh = cm
			c.material_override = _mat
			c.visible = false
			add_child(c)
			_chappals.append(c)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.55
			tm.outer_radius = 0.7
			ring.mesh = tm
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(1, 0.15, 0.1, 0.8)
			rm.emission_enabled = true
			rm.emission = Color(1, 0.1, 0.05)
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.material_override = rm
			ring.scale = Vector3(1, 0.1, 0.8)
			ring.visible = false
			add_child(ring)
			_rings.append(ring)
	_bake_templates()


func _mesh(m: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat if mat else _mat
	return mi


func _make_hazard(i: int, o: Dictionary) -> Node3D:
	var kind := String(o.kind)
	var look: int = o.look
	var n := Node3D.new()
	match kind:
		"rickshaw", "wrongway":
			var body := _mesh(V.get_mesh("rickshaw", look))
			n.add_child(body)
			if kind == "wrongway":
				body.rotation.y = PI
			var dir := -1.0 if kind == "wrongway" else 1.0
			# A sitting person's hips stay at standing height (~0.85 m above
			# their feet), so the root goes that far below the seat.
			_want(n, "driver_%d" % (look % 2), Transform3D(Basis.from_euler(Vector3(0, 0 if dir > 0 else PI, 0)), Vector3(0.3 * dir, 0.2, 0)))
			_want(n, "sit_%d" % (look % 3), Transform3D(Basis.from_euler(Vector3(0, 0 if dir > 0 else PI, 0)), Vector3(-0.8 * dir, 0.27, 0.22)))
			_want(n, "sit_%d" % ((look + 1) % 3), Transform3D(Basis.from_euler(Vector3(0, 0 if dir > 0 else PI, 0)), Vector3(-0.8 * dir, 0.27, -0.22)))
		"wagon":
			n.add_child(_mesh(V.get_mesh("wagon", look)))
			_want(n, "hang", Transform3D(Basis(), Vector3(0.55, 0.32, 1.05)))
		"bus":
			n.add_child(_mesh(V.get_mesh("bus", look)))
			_want(n, "sit_roof", Transform3D(Basis(), Vector3(1.8, 2.55, 0.2)))
		"cart", "eggs":
			n.add_child(_mesh(V.get_mesh(kind, look)))
			_want(n, "push", Transform3D(Basis(), Vector3(-1.95, 0.0, 0.0)))
			if kind == "eggs":
				var l := Label3D.new()
				l.text = "ANDA SHAMI BURGER"
				l.font_size = 64
				l.pixel_size = 0.0045
				l.modulate = Color(0.75, 0.05, 0.05)
				l.shaded = false
				l.position = Vector3(0, 1.76, -0.5)
				n.add_child(l)
		"ramp", "breaker", "pothole":
			n.add_child(_mesh(V.get_mesh(kind, look)))
			if kind == "breaker":
				n.position.z = 0.0
		"puddle":
			var mi := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 1.6
			cy.bottom_radius = 1.6
			cy.height = 0.01
			mi.mesh = cy
			mi.scale = Vector3(1.0, 1.0, 0.65)
			mi.material_override = _puddle_mat
			mi.position.y = 0.008
			n.add_child(mi)
		"goats":
			for g in 3:
				var gm := _mesh(V.get_mesh("goat", look + g))
				gm.position = Vector3(-0.9 + g * 0.9, 0, (g - 1) * 0.35)
				gm.rotation.y = 0.0 if (look + g) % 2 == 0 else PI
				n.add_child(gm)
		"pigeons":
			for b in 7:
				var hs := absi(hash(look * 13 + b))
				var bird := Node3D.new()
				bird.position = Vector3(-1.2 + (hs % 25) / 10.0, 0, -0.9 + ((hs >> 5) % 18) / 10.0)
				bird.rotation.y = TAU * float((hs >> 9) % 100) / 100.0
				bird.add_child(_mesh(V.get_mesh("pigeon", 0)))
				for side in [-1.0, 1.0]:
					var w := _mesh(V.get_mesh("wing", 0))
					w.position = Vector3(0, 0.15, 0.05 * side)
					w.rotation.x = 0.0 if side > 0 else PI
					w.visible = false
					bird.add_child(w)
				n.add_child(bird)
		"baraat":
			var horse := _mesh(V.get_mesh("horse", 0))
			horse.position = Vector3(-1.0, 0, 1.6)
			n.add_child(horse)
			_want(n, "dulha", Transform3D(Basis(), Vector3(-1.05, 0.62, 1.6)))
			_want(n, "dhol", Transform3D(Basis(), Vector3(1.0, 0.0, 1.2)))
			for k in 3:
				_want(n, "dancer_%d" % k, Transform3D(Basis.from_euler(Vector3(0, PI / 2.0, 0)), Vector3(-2.5 + k * 1.3, 0.0, -0.9 + k * 0.6)))
			_want(n, "lights", Transform3D(Basis(), Vector3(3.2, 0.0, -1.8)))
			for k in 5:
				var bulb := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.08
				sm.height = 0.16
				bulb.mesh = sm
				var bm := StandardMaterial3D.new()
				bm.emission_enabled = true
				bm.emission = [Color(1, 0.3, 0.3), Color(1, 1, 0.4), Color(0.4, 1, 0.5), Color(0.4, 0.7, 1), Color(1, 0.5, 1)][k]
				bm.emission_energy_multiplier = 2.0
				bulb.material_override = bm
				bulb.position = Vector3(2.8 + k * 0.2, 2.9, -1.8)
				n.add_child(bulb)
		"ped":
			var p := Person.new()
			p.role = ["uncle", "uncle", "aunty", "kid", "oldman"][look % 5]
			p.look = look
			p.face_dir = 0.0
			n.add_child(p)
			_people[i] = p
	return n


func _want(parent: Node3D, template: String, xf: Transform3D) -> void:
	_waiting.append([parent, template, xf])


# ---------------------------------------------------------------- baked people

const TEMPLATES := {
	"driver_0": ["driver", 2, "sit"], "driver_1": ["driver", 5, "sit"],
	"sit_0": ["uncle", 0, "sit"], "sit_1": ["aunty", 1, "sit"], "sit_2": ["oldman", 4, "sit"],
	"sit_roof": ["uncle", 6, "sit"], "hang": ["uncle", 3, "hang"], "push": ["uncle", 7, "push"],
	"dulha": ["dulha", 0, "sit"], "dhol": ["dhol", 2, "idle"], "lights": ["uncle", 5, "idle"],
	"dancer_0": ["uncle", 1, "cheer"], "dancer_1": ["aunty", 2, "cheer"], "dancer_2": ["kid", 3, "cheer"],
}


func _bake_templates() -> void:
	var needed := {}
	for w in _waiting:
		needed[w[1]] = true
	var made: Array = []
	for key in needed:
		if _templates.has(key):
			continue
		var spec: Array = TEMPLATES[key]
		var p := Person.new()
		p.role = spec[0]
		p.look = spec[1]
		p.position = Vector3(0, -50, 0)
		add_child(p)
		made.append([key, p, spec[2]])
	if not made.is_empty():
		var built_for = ride
		await get_tree().process_frame
		# A new ride may have started meanwhile (and freed these): give up.
		for m in made:
			if not is_instance_valid(m[1]) or built_for != ride:
				return
			(m[1] as Person).play(m[2], 1.0, 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		for m in made:
			if not is_instance_valid(m[1]) or built_for != ride:
				return
			_templates[m[0]] = _bake(m[1])
			(m[1] as Node).queue_free()
	for w in _waiting:
		var parent: Node3D = w[0]
		if not is_instance_valid(parent) or not _templates.has(w[1]):
			continue
		var copy: Node3D = (_templates[w[1]] as Node3D).duplicate()
		copy.transform = w[2]
		parent.add_child(copy)
	_waiting.clear()


## Freezes a posed person into static meshes (no skeleton work per frame).
func _bake(p: Person) -> Node3D:
	var out := Node3D.new()
	var inv := p.global_transform.affine_inverse()
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var copy := MeshInstance3D.new()
		if m.skin != null or String(m.skeleton) != "":
			copy.mesh = m.bake_mesh_from_current_skeleton_pose()
			for s in m.get_surface_override_material_count():
				copy.set_surface_override_material(s, m.get_surface_override_material(s))
		else:
			copy.mesh = m.mesh
			copy.material_override = m.material_override
		copy.transform = inv * m.global_transform
		out.add_child(copy)
	return out


# ---------------------------------------------------------------- each frame

func sync(r, delta: float) -> void:
	if r != ride:
		return
	var t: float = ride.t
	var cam_x: float = ride.x
	for i in _nodes:
		var o: Dictionary = ride.hazards[i]
		var n: Node3D = _nodes[i]
		var ox: float = o.x
		var vis := ox > cam_x - 16.0 and ox < cam_x + 45.0
		if vis != n.visible:
			n.visible = vis
			# Hidden people stop animating too (skinned meshes cost CPU).
			n.process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED
		if not vis:
			continue
		var kind := String(o.kind)
		var od: float = o.d
		n.position = Vector3(ox, 0.0, -od)
		match kind:
			"rickshaw", "wrongway", "wagon", "bus":
				n.position.y = absf(sin(t * 12.0 + float(o.look))) * 0.02
			"breaker":
				n.position.z = 0.0
			"ped":
				_sync_ped(i, o)
			"goats":
				var walking: bool = o.state == "walk" or o.state == "scared"
				for g in n.get_child_count():
					var gm: Node3D = n.get_child(g)
					gm.position.y = absf(sin(t * (12.0 if walking else 2.0) + g)) * (0.06 if walking else 0.01)
			"pigeons":
				_sync_pigeons(n, o, t)
	_sync_bike(ride)
	if _warden:
		var w: Dictionary = ride.warden
		_warden.position = Vector3(float(w.x), 0.0, -float(w.d))
		_warden.set_motion(float(w.x), 0.0, 0.0, float(w.v), t)
	_sync_crowd(t)
	if _ammi:
		_sync_ammi(t)


func _sync_ped(i: int, o: Dictionary) -> void:
	var p: Person = _people[i]
	var on_path: bool = not ride._on_road(o)
	p.position.y = 0.2 if on_path else 0.0
	match String(o.state):
		"walk":
			p.play("walk")
		"scared":
			p.play("run", 1.3)
		_:
			p.play("idle")
	# Face the way they're crossing (toward the camera is +Z = -d).
	var to: float = o.get("to", 0.0)
	p.rotation.y = 0.0 if to < float(o.d) else PI


func _sync_pigeons(n: Node3D, o: Dictionary, t: float) -> void:
	var flying: bool = o.state == "fly"
	var since: float = t - float(o.get("fly_t", t))
	for b in n.get_child_count():
		var bird: Node3D = n.get_child(b)
		var hs := absi(hash(int(o.look) * 13 + b))
		if flying:
			bird.position.y = since * (2.5 + (hs % 4) * 0.6)
			bird.position.x = -1.2 + (hs % 25) / 10.0 + since * (2.0 + (hs % 5)) * (1.0 if hs % 2 == 0 else -0.6)
			bird.visible = bird.position.y < 14.0
			for w in [1, 2]:
				var wing: Node3D = bird.get_child(w)
				wing.visible = true
				wing.rotation.x = (0.0 if w == 1 else PI) + sin(t * 30.0 + b) * 0.9 * (1.0 if w == 1 else -1.0)
		else:
			bird.position.y = 0.0
			bird.get_child(0).rotation.z = -0.4 if fmod(t * 2.0 + b * 0.37, 1.0) < 0.2 else 0.0


## The crowd: the pooled spectators stand on whichever crowd spots are near
## the camera, cheering when the ride says so.
func _sync_crowd(_t: float) -> void:
	var near: Array = []
	for c in ride.crowd:
		var cx: float = c.x
		if cx > ride.x - 12.0 and cx < ride.x + 34.0:
			near.append(c)
	for k in _crowd.size():
		var p: Person = _crowd[k]
		if k >= near.size():
			if p.visible:
				p.visible = false
				p.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		if not p.visible:
			p.process_mode = Node.PROCESS_MODE_INHERIT
		var c: Dictionary = near[k]
		p.visible = true
		p.position = Vector3(float(c.x), 0.2, -float(c.d))
		p.play("cheer" if float(c.cheer) > 0.0 else "idle")


func _sync_ammi(t: float) -> void:
	_ammi.position = Vector3(float(ride.ammi_x), Ride.AMMI_H, -Ride.AMMI_D)
	_ledge.position = Vector3(float(ride.ammi_x), Ride.AMMI_H - 0.08, -Ride.AMMI_D)
	if ride.chappals.size() > _throws:
		_throws = ride.chappals.size()
		_ammi.play("throw", 1.0, 0.05)
		_ammi.anim.seek(0.0, true)
	elif not _ammi.anim.is_playing():
		_ammi.play("idle")
	var list: Array = ride.chappals
	for k in _chappals.size():
		var c: MeshInstance3D = _chappals[k]
		var ring: MeshInstance3D = _rings[k]
		var idx := list.size() - 1 - k
		if idx < 0:
			c.visible = false
			ring.visible = false
			continue
		var ch: Dictionary = list[idx]
		c.visible = true
		if ch.landed:
			c.position = Vector3(float(ch.tx), 0.02, -float(ch.td))
			c.rotation = Vector3(0, 0.3, 0)
			ring.visible = false
		else:
			var pos: Vector3 = ride.chappal_pos(ch)
			c.position = Vector3(pos.x, pos.z, -pos.y)
			c.rotation = Vector3(t * 9.0, t * 4.0, 0)
			ring.visible = true
			var f: float = clampf((t - float(ch.t0)) / Ride.CHAPPAL_FLIGHT, 0.0, 1.0)
			ring.position = Vector3(float(ch.tx), 0.03, -float(ch.td))
			var s := 1.3 - f * 0.5
			ring.scale = Vector3(s, 0.1, s * 0.8)


## Shani: riding, posing for tricks, and the crash, where the bike skids on
## its side and he flies down the road, then gets back on.
func _sync_bike(r) -> void:
	var t: float = r.t
	var crashed: bool = float(r.crash_t) > 0.0
	_bike.visible = not (float(r.safe_t) > 0.0 and fmod(t, 0.2) < 0.1)
	var p := _bike.person
	if crashed:
		var tc: float = Ride.CRASH_TIME - float(r.crash_t)
		_bike.position = Vector3(float(r.x), 0.0, -float(r.d))
		var tip := minf(1.0, tc / 0.45)
		_bike.set_motion(float(r.x), 0.0, 0.0, 0.0, t)
		_bike.rotation = Vector3(-tip * PI / 2.0 * 0.92, 0, 0)
		if _pose != "crash":
			_pose = "crash"
			p.play("fall", 1.4, 0.05)
			p.top_level = true
		var air := minf(tc, 0.76)
		var cv: float = r.crash_v
		p.global_position = Vector3(float(r.x) + 1.0 + air * cv * 0.45, maxf(0.0, 1.0 + 4.0 * air - 7.0 * air * air), -float(r.d))
		p.global_rotation = Vector3(0, 0, -air * 9.0 if tc < 0.76 else 0.0)
		return
	if _pose == "crash":
		p.top_level = false
		p.position = Vector3.ZERO
		p.rotation = Vector3.ZERO
	_bike.rotation = Vector3.ZERO
	_bike.position = Vector3(float(r.x), float(r.h), -float(r.d))
	var wob := sin(t * 40.0) * 0.06 if float(r.wobble_t) > 0.0 else 0.0
	_bike.set_motion(float(r.x), float(r.pitch), wob, float(r.v), t)
	var want := String(r.trick) if String(r.trick) != "" else "ride"
	if want != _pose:
		_pose = want
		_bike.pose(want)
