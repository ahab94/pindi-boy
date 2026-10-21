extends Node3D
## A person in 3D: the CC0 Quaternius "Casual" model (see CREDITS.md),
## recoloured and dressed in code for each role, and animated with its own
## clips (Walk, Idle, Run, Death) plus the riding poses in rider_poses.gd.
##
## Roles: "shani", "uncle", "aunty", "kid", "oldman", "warden", "ammi",
## "driver", "dulha", "dhol".
##
## Godot notes:
## - A skinned mesh is deformed by a Skeleton3D: each vertex follows a few
##   bones; animations are tracks that rotate those bones over time.
## - BoneAttachment3D makes a node follow a bone: that's how shades, caps,
##   dupattas and kameez flaps ride along with the body.
## - Character space here: metres, Y up, facing +Z (before scaling). The
##   whole model is turned to face +X, the way Shani rides.

const Poses := preload("res://scripts/rider_poses.gd")
const MODEL := preload("res://assets/characters/Casual.glb")

const SKIN := Color("#c68a5e")
const SKIN_DARK := Color("#9c6440")
const HAIR := Color("#140f0d")

var role := "uncle"
var look := 0
var height := 0.95            # model scale (the base model is a tall adult)
var face_dir := 1.0           # +1 faces +X (along the road), -1 faces -X, 0 faces the camera
var skeleton: Skeleton3D
var anim: AnimationPlayer
var _model: Node3D
var _armature: Node3D
var _flaps: Array = []        # kameez flaps that flutter with speed
var _current := ""
var _phone: Node3D


func _ready() -> void:
	_model = MODEL.instantiate()
	_model.scale = Vector3.ONE * height
	_model.rotation.y = PI / 2.0 if face_dir > 0.0 else (-PI / 2.0 if face_dir < 0.0 else 0.0)
	add_child(_model)
	skeleton = _model.find_child("Skeleton3D", true, false)
	anim = _model.find_child("AnimationPlayer", true, false)
	_armature = skeleton.get_parent()
	Poses.add_library(anim, skeleton, _armature)
	_dress()


func play(name: String, speed := 1.0, blend := 0.15) -> void:
	var clip := name
	match name:
		"walk": clip = "CharacterArmature|Walk"
		"run": clip = "CharacterArmature|Run"
		"idle": clip = "CharacterArmature|Idle"
		"wave": clip = "CharacterArmature|Wave"
		"hit": clip = "CharacterArmature|HitRecieve"
		"fall": clip = "CharacterArmature|Death"
		_: clip = "ride/" + name
	if _phone:
		_phone.visible = name == "selfie"
	if clip == _current:
		anim.speed_scale = speed
		return
	_current = clip
	anim.play(clip, blend)
	anim.speed_scale = speed


## Speed makes the kameez flap: more wind, more flutter.
func flutter(t: float, wind: float) -> void:
	for i in _flaps.size():
		var f: Node3D = _flaps[i]
		var base: Basis = f.get_meta("base")
		var amp := clampf(wind / 12.0, 0.0, 1.0) * 0.5
		f.basis = base * Basis.from_euler(Vector3(-amp * (0.7 + 0.3 * sin(t * (9.0 + wind) + i)), 0, 0))


# ---------------------------------------------------------------- outfits

func _dress() -> void:
	var c := _palette()
	_recolour(c)
	var head := _bone_char_pos("Head")
	match role:
		"shani":
			_kameez_flaps(c.shirt, 0.42)
			_shades(head)
			_spikes(head)
			_phone = _box_on("Wrist.R", Vector3(0.07, 0.13, 0.012), Color(0.08, 0.08, 0.1), _bone_char_pos("Wrist.R") + Vector3(0, 0.1, 0.03))
			_phone.visible = false
		"uncle", "oldman":
			_kameez_flaps(c.shirt, 0.5)
			_waistcoat(Color(0.22, 0.2, 0.18) if look % 2 == 0 else Color(0.35, 0.25, 0.18))
			_moustache(head)
			if role == "oldman":
				_cap(head, Color(0.95, 0.95, 0.95), 0.05)
		"aunty", "ammi":
			_kameez_flaps(c.shirt, 0.62)
			_dupatta(head, c.dupatta)
		"kid":
			_kameez_flaps(c.shirt, 0.3)
		"warden":
			_cap(head, Color(0.97, 0.97, 0.97), 0.09, true)
			_moustache(head)
		"driver":
			_kameez_flaps(c.shirt, 0.4)
			_cap(head, Color(0.95, 0.95, 0.95), 0.05)
			_moustache(head)
		"dulha":
			_kameez_flaps(c.shirt, 0.75)
			_turban(head)
		"dhol":
			_kameez_flaps(c.shirt, 0.5)
			_moustache(head)


func _palette() -> Dictionary:
	var shirts := [Color("#f2efe6"), Color("#8fb8d8"), Color("#b39572"), Color("#7d8a7a"), Color("#d98a96"),
		Color("#5b6a92"), Color("#d8c88a"), Color("#9a4e4e")]
	var shirt: Color = shirts[look % shirts.size()]
	var trouser := shirt.lightened(0.08)
	var skin := SKIN if look % 3 != 0 else SKIN_DARK
	var dup: Color = [Color("#f07c2a"), Color("#3aa060"), Color("#c23a7a"), Color("#e8c23a")][look % 4]
	match role:
		"shani":
			shirt = Color("#6fb4ee")
			trouser = Color("#86c3f2")
			skin = SKIN
		"warden":
			shirt = Color("#24366e")
			trouser = Color("#1c2236")
		"ammi":
			shirt = Color("#8c2c55")
			trouser = Color("#a03a62")
			dup = Color("#2f8f55")
		"dulha":
			shirt = Color("#f3e3b8")
			trouser = Color("#f6efe0")
		"aunty":
			shirt = [Color("#e05a7a"), Color("#e8a23a"), Color("#4a9ad8"), Color("#9a5ac8")][look % 4]
			trouser = shirt.lightened(0.15)
	return {"shirt": shirt, "trouser": trouser, "skin": skin, "dupatta": dup}


func _recolour(c: Dictionary) -> void:
	var map := {
		"LightBrown": [c.shirt, 0.85], "LightBlue": [c.trouser, 0.9],
		"Skin": [c.skin, 0.65], "Skin_Darker": [(c.skin as Color).darkened(0.1), 0.65],
		"Hair": [HAIR, 0.5], "Eyebrows": [HAIR, 0.6], "Eye": [Color("#140c08"), 0.25],
		"White": [Color("#6e4122"), 0.7], "Red_Dark": [Color("#3a2416"), 0.8],
	}
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var name := m.mesh.surface_get_material(s).resource_name
			if map.has(name):
				m.set_surface_override_material(s, _mat(map[name][0], map[name][1]))


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.6
	return m


## Character space -> a bone attachment's local transform.
func _local_to_bone(bone: String, char_xform: Transform3D) -> Transform3D:
	var g := skeleton.get_bone_global_rest(skeleton.find_bone(bone))
	return g.affine_inverse() * _armature.transform.affine_inverse() * char_xform


func _bone_char_pos(bone: String) -> Vector3:
	return _armature.transform * skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin


func _attach(bone: String, node: Node3D, char_xform: Transform3D) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	node.transform = _local_to_bone(bone, char_xform)
	ba.add_child(node)


func _mesh_node(mesh: Mesh, col: Color, rough := 0.8, two_sided := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _mat(col, rough)
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _box_on(bone: String, size: Vector3, col: Color, at: Vector3, basis := Basis()) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _mesh_node(b, col)
	_attach(bone, mi, Transform3D(basis, at))
	return mi


## The long kameez: a front and a back panel hanging from the hips down to
## `length` below them. The back one flutters in the wind (flutter()).
func _kameez_flaps(col: Color, length: float) -> void:
	var hips := _bone_char_pos("Hips")
	for side in [1.0, -1.0]:
		var pivot := Node3D.new()
		var panel := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(0.36, length, 0.02)
		panel.mesh = q
		var m := _mat(col, 0.85)
		panel.material_override = m
		panel.position = Vector3(0, -length / 2.0, 0)
		pivot.add_child(panel)
		var at := hips + Vector3(0, 0.08, 0.09 * side + 0.04)
		_attach("Hips", pivot, Transform3D(Basis.from_euler(Vector3(0.12 * side, 0, 0)), at))
		pivot.set_meta("base", pivot.basis)
		if side < 0.0:
			_flaps.append(pivot)
	# Side slits are where the two panels part; a short skirt joins them up top.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.2
	cyl.height = 0.22
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 16
	_attach("Hips", _mesh_node(cyl, col, 0.85, true), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.8)), hips + Vector3(0, -0.02, 0.05)))


func _waistcoat(col: Color) -> void:
	var chest := _bone_char_pos("Chest")
	for side in [-1.0, 1.0]:
		_box_on("Chest", Vector3(0.15, 0.42, 0.26), col, chest + Vector3(0.1 * side, -0.05, 0.03))


func _shades(head: Vector3) -> void:
	_box_on("Head", Vector3(0.2, 0.05, 0.03), Color(0.02, 0.02, 0.04), head + Vector3(0, 0.12, 0.14))


func _spikes(head: Vector3) -> void:
	for i in 6:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.045
		cone.height = 0.12 + (i % 3) * 0.03
		cone.radial_segments = 6
		var mi := _mesh_node(cone, HAIR, 0.4)
		var a := -0.5 + i * 0.2
		_attach("Head", mi, Transform3D(Basis.from_euler(Vector3(-0.5 - a * 0.3, 0, 0.3 * (i % 2 * 2 - 1))), head + Vector3((i % 2) * 0.06 - 0.03, 0.27, 0.02 - a * 0.1)))


func _moustache(head: Vector3) -> void:
	_box_on("Head", Vector3(0.11, 0.025, 0.02), HAIR, head + Vector3(0, 0.035, 0.145))


func _cap(head: Vector3, col: Color, h: float, peak := false) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.125
	cyl.height = h
	_attach("Head", _mesh_node(cyl, col), Transform3D(Basis(), head + Vector3(0, 0.27, 0)))
	if peak:
		_box_on("Head", Vector3(0.2, 0.015, 0.1), Color(0.1, 0.1, 0.12), head + Vector3(0, 0.23, 0.13))


func _dupatta(head: Vector3, col: Color) -> void:
	var sp := SphereMesh.new()
	sp.radius = 0.16
	sp.height = 0.3
	sp.is_hemisphere = true
	_attach("Head", _mesh_node(sp, col, 0.9, true), Transform3D(Basis.from_scale(Vector3(1.05, 1.0, 1.1)), head + Vector3(0, 0.15, -0.01)))
	# The long end draped over a shoulder and down the back.
	var b := BoxMesh.new()
	b.size = Vector3(0.3, 0.75, 0.02)
	_attach("Chest", _mesh_node(b, col, 0.9, true), Transform3D(Basis.from_euler(Vector3(0.25, 0, 0)), _bone_char_pos("Chest") + Vector3(0, -0.05, -0.16)))


func _turban(head: Vector3) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.08
	t.outer_radius = 0.16
	_attach("Head", _mesh_node(t, Color("#e8b030"), 0.5), Transform3D(Basis.from_scale(Vector3(1, 1.4, 1)), head + Vector3(0, 0.22, 0)))
	# The sehra: strings of flowers hanging over the face.
	for i in 7:
		_box_on("Head", Vector3(0.012, 0.24, 0.012), Color(1, 1, 1), head + Vector3(-0.09 + i * 0.03, 0.05, 0.16))
