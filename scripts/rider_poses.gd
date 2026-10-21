extends RefCounted
## Shani's riding poses, which the base model doesn't have, built in code as
## Animation resources and added to the model's AnimationPlayer as the
## library "ride". (Adapted from Bo Kaata's kid poses.)
##
## Each pose is a list of bone rotations in character space, in degrees:
##   x = pitch (positive tips the bone's far end forward; thighs and arms
##       use negative to swing forward/up, shins positive to bend the knee),
##   y = turn, z = roll (positive swings the left arm out sideways and up;
##       the right arm uses negative).
## A pose sits on top of a frame of the Idle clip and is converted into each
## bone's own frame, and a child bone's rotation stacks on its parent's, like
## moving a puppet joint by joint.

const BASE_CLIP := "CharacterArmature|Idle"

# Sitting on the bike, leaning into the bars, elbows out, a little bob.
const RIDE := {"len": 0.6, "loop": true, "keys": [
	[0.0, {"Body": [18, 0, 0], "Head": [-14, 0, 0], "Neck": [-6, 0, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-62, 0, 18], "LowerArm.L": [-28, 0, 0], "UpperArm.R": [-62, 0, -18], "LowerArm.R": [-28, 0, 0]}],
	[0.3, {"Body": [20, 0, 0], "Head": [-16, 0, 0], "Neck": [-6, 0, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-64, 0, 18], "LowerArm.L": [-24, 0, 0], "UpperArm.R": [-64, 0, -18], "LowerArm.R": [-24, 0, 0]}],
	[0.6, {"Body": [18, 0, 0], "Head": [-14, 0, 0], "Neck": [-6, 0, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-62, 0, 18], "LowerArm.L": [-28, 0, 0], "UpperArm.R": [-62, 0, -18], "LowerArm.R": [-28, 0, 0]}],
]}

# Both hands up, shouting.
const NO_HANDS := {"len": 0.5, "loop": true, "keys": [
	[0.0, {"Body": [-4, 0, 0], "Head": [-18, 0, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-15, 0, 150], "LowerArm.L": [-15, 0, 0], "UpperArm.R": [-15, 0, -150], "LowerArm.R": [-15, 0, 0]}],
	[0.25, {"Body": [-6, 0, 0], "Head": [-22, 0, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-15, 0, 165], "LowerArm.L": [-5, 0, 0], "UpperArm.R": [-15, 0, -165], "LowerArm.R": [-5, 0, 0]}],
	[0.5, {"Body": [-4, 0, 0], "Head": [-18, 0, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-15, 0, 150], "LowerArm.L": [-15, 0, 0], "UpperArm.R": [-15, 0, -150], "LowerArm.R": [-15, 0, 0]}],
]}

# Flat out behind the bars, legs streaming back.
const SUPERMAN := {"len": 0.5, "loop": true, "keys": [
	[0.0, {"Body": [78, 0, 0], "Head": [-60, 0, 0], "Neck": [-15, 0, 0],
		"UpperLeg.L": [6, 0, 4], "LowerLeg.L": [4, 0, 0], "UpperLeg.R": [-2, 0, -4], "LowerLeg.R": [8, 0, 0],
		"UpperArm.L": [-12, 0, 10], "LowerArm.L": [0, 0, 0], "UpperArm.R": [-12, 0, -10], "LowerArm.R": [0, 0, 0]}],
	[0.25, {"Body": [80, 0, 0], "Head": [-60, 0, 0], "Neck": [-15, 0, 0],
		"UpperLeg.L": [-2, 0, 4], "LowerLeg.L": [8, 0, 0], "UpperLeg.R": [6, 0, -4], "LowerLeg.R": [4, 0, 0],
		"UpperArm.L": [-12, 0, 10], "LowerArm.L": [0, 0, 0], "UpperArm.R": [-12, 0, -10], "LowerArm.R": [0, 0, 0]}],
	[0.5, {"Body": [78, 0, 0], "Head": [-60, 0, 0], "Neck": [-15, 0, 0],
		"UpperLeg.L": [6, 0, 4], "LowerLeg.L": [4, 0, 0], "UpperLeg.R": [-2, 0, -4], "LowerLeg.R": [8, 0, 0],
		"UpperArm.L": [-12, 0, 10], "LowerArm.L": [0, 0, 0], "UpperArm.R": [-12, 0, -10], "LowerArm.R": [0, 0, 0]}],
]}

# Standing on the seat, arms out like a bird, knees soft.
const SEAT_STAND := {"len": 0.6, "loop": true, "keys": [
	[0.0, {"Head": [-10, 0, 0], "UpperLeg.L": [-14, 0, 4], "LowerLeg.L": [22, 0, 0],
		"UpperLeg.R": [-14, 0, -4], "LowerLeg.R": [22, 0, 0],
		"UpperArm.L": [0, 0, 92], "LowerArm.L": [0, 0, 0], "UpperArm.R": [0, 0, -92], "LowerArm.R": [0, 0, 0]}],
	[0.3, {"Head": [-12, 0, 0], "UpperLeg.L": [-14, 0, 4], "LowerLeg.L": [22, 0, 0],
		"UpperLeg.R": [-14, 0, -4], "LowerLeg.R": [22, 0, 0], "Body": [0, 0, 4],
		"UpperArm.L": [0, 0, 100], "LowerArm.L": [0, 0, 0], "UpperArm.R": [0, 0, -84], "LowerArm.R": [0, 0, 0]}],
	[0.6, {"Head": [-10, 0, 0], "UpperLeg.L": [-14, 0, 4], "LowerLeg.L": [22, 0, 0],
		"UpperLeg.R": [-14, 0, -4], "LowerLeg.R": [22, 0, 0],
		"UpperArm.L": [0, 0, 92], "LowerArm.L": [0, 0, 0], "UpperArm.R": [0, 0, -92], "LowerArm.R": [0, 0, 0]}],
]}

# Seated, right arm stretched up and forward with the phone, head turned
# to the camera, left hand on the bar.
const SELFIE := {"len": 0.6, "loop": true, "keys": [
	[0.0, {"Body": [8, 0, 0], "Head": [-8, 35, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-62, 0, 18], "LowerArm.L": [-28, 0, 0], "UpperArm.R": [-135, 0, -25], "LowerArm.R": [-8, 0, 0]}],
	[0.6, {"Body": [8, 0, 0], "Head": [-10, 38, 0],
		"UpperLeg.L": [-82, 0, 6], "LowerLeg.L": [88, 0, 0], "UpperLeg.R": [-82, 0, -6], "LowerLeg.R": [88, 0, 0],
		"UpperArm.L": [-62, 0, 18], "LowerArm.L": [-28, 0, 0], "UpperArm.R": [-138, 0, -25], "LowerArm.R": [-6, 0, 0]}],
]}

# Sprawled on the road after a crash: arms and legs everywhere.
const SPLAT := {"len": 0.4, "loop": false, "keys": [
	[0.0, {"Body": [-80, 0, 0], "Head": [10, 0, 0], "UpperArm.L": [0, 0, 120], "UpperArm.R": [0, 0, -100],
		"UpperLeg.L": [-30, 0, 20], "LowerLeg.L": [40, 0, 0], "UpperLeg.R": [-10, 0, -25], "LowerLeg.R": [10, 0, 0]}],
]}

# Sitting in a rickshaw or on a bench, hands on knees.
const SIT := {"len": 1.0, "loop": true, "keys": [
	[0.0, {"Body": [4, 0, 0], "UpperLeg.L": [-88, 0, 6], "LowerLeg.L": [90, 0, 0],
		"UpperLeg.R": [-88, 0, -6], "LowerLeg.R": [90, 0, 0],
		"UpperArm.L": [-30, 0, 8], "LowerArm.L": [-45, 0, 0], "UpperArm.R": [-30, 0, -8], "LowerArm.R": [-45, 0, 0]}],
]}

# Cheering on the footpath: both arms up, a bounce.
const CHEER := {"len": 0.5, "loop": true, "hop": 0.06, "keys": [
	[0.0, {"UpperArm.L": [-10, 0, 140], "LowerArm.L": [-20, 0, 0], "UpperArm.R": [-10, 0, -140], "LowerArm.R": [-20, 0, 0], "Head": [-10, 0, 0]}],
	[0.25, {"UpperArm.L": [-10, 0, 165], "LowerArm.L": [0, 0, 0], "UpperArm.R": [-10, 0, -165], "LowerArm.R": [0, 0, 0], "Head": [-14, 0, 0]}],
	[0.5, {"UpperArm.L": [-10, 0, 140], "LowerArm.L": [-20, 0, 0], "UpperArm.R": [-10, 0, -140], "LowerArm.R": [-20, 0, 0], "Head": [-10, 0, 0]}],
]}

# Pushing a thela: standing, arms forward to the handles.
const PUSH := {"len": 1.0, "loop": true, "keys": [
	[0.0, {"Body": [10, 0, 0], "UpperArm.L": [-55, 0, 12], "LowerArm.L": [-20, 0, 0],
		"UpperArm.R": [-55, 0, -12], "LowerArm.R": [-20, 0, 0]}],
]}

# The wagon conductor hanging out of the door, one arm out, shouting.
const HANG := {"len": 1.0, "loop": true, "keys": [
	[0.0, {"Body": [0, 0, -12], "UpperArm.R": [0, 0, -120], "LowerArm.R": [-10, 0, 0],
		"UpperArm.L": [-90, 0, 40], "LowerArm.L": [-30, 0, 0], "Head": [0, -20, 0]}],
]}

# Ammi winding up and hurling a chappal.
const THROW := {"len": 0.5, "loop": false, "keys": [
	[0.0, {"Body": [-10, 0, 0], "UpperArm.R": [40, 0, -150], "LowerArm.R": [-40, 0, 0], "UpperArm.L": [0, 0, 30]}],
	[0.2, {"Body": [15, 0, 0], "UpperArm.R": [-120, 0, -30], "LowerArm.R": [0, 0, 0], "UpperArm.L": [0, 0, 30]}],
	[0.5, {"Body": [5, 0, 0], "UpperArm.R": [-60, 0, -20], "LowerArm.R": [-20, 0, 0], "UpperArm.L": [0, 0, 30]}],
]}

const BONES := ["Body", "Hips", "Abdomen", "Torso", "Chest", "Neck", "Head",
	"Shoulder.L", "UpperArm.L", "LowerArm.L", "Wrist.L",
	"Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R",
	"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"]
# The feet hang off the root bone (the rig's IK setup), not the shins, so
# they're placed by forward kinematics: wherever the posed shin puts the ankle.
const FEET := {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}


static var _library: AnimationLibrary   # built once, shared by every character


static func add_library(ap: AnimationPlayer, sk: Skeleton3D, armature: Node3D) -> void:
	if _library == null:
		_library = _make_library(ap, sk, armature)
	ap.add_animation_library("ride", _library)


static func _make_library(ap: AnimationPlayer, sk: Skeleton3D, armature: Node3D) -> AnimationLibrary:
	var base_anim := ap.get_animation(BASE_CLIP)
	var prefix := String(base_anim.track_get_path(0)).split(":")[0]
	var lib := AnimationLibrary.new()
	var ctx := {"sk": sk, "base": base_anim, "prefix": prefix,
		"A": armature.transform.basis.orthonormalized(),
		"A_inv_full": armature.transform.affine_inverse().basis}
	for pair in [["ride", RIDE], ["no_hands", NO_HANDS], ["superman", SUPERMAN], ["seat_stand", SEAT_STAND],
			["selfie", SELFIE], ["splat", SPLAT], ["sit", SIT], ["cheer", CHEER], ["throw", THROW],
			["push", PUSH], ["hang", HANG]]:
		lib.add_animation(pair[0], _build(ctx, pair[1]))
	return lib


## The base frame's local rotation for a bone (from the base clip, else rest).
static func _base_rot(ctx: Dictionary, bone: String) -> Quaternion:
	var a: Animation = ctx.base
	var t := a.find_track(NodePath(ctx.prefix + ":" + bone), Animation.TYPE_ROTATION_3D)
	if t >= 0:
		return a.rotation_track_interpolate(t, 0.0)
	var sk: Skeleton3D = ctx.sk
	return sk.get_bone_rest(sk.find_bone(bone)).basis.get_rotation_quaternion()


static func _base_pos(ctx: Dictionary, bone: String) -> Vector3:
	var a: Animation = ctx.base
	var t := a.find_track(NodePath(ctx.prefix + ":" + bone), Animation.TYPE_POSITION_3D)
	if t >= 0:
		return a.position_track_interpolate(t, 0.0)
	var sk: Skeleton3D = ctx.sk
	return sk.get_bone_rest(sk.find_bone(bone)).origin


## The base frame's rotation of a bone in skeleton space (its parents' base
## rotations chained together).
static func _base_global(ctx: Dictionary, bone: String) -> Quaternion:
	var sk: Skeleton3D = ctx.sk
	var i := sk.find_bone(bone)
	var q := Quaternion.IDENTITY
	while i >= 0:
		q = _base_rot(ctx, sk.get_bone_name(i)) * q
		i = sk.get_bone_parent(i)
	return q


static func _build(ctx: Dictionary, spec: Dictionary) -> Animation:
	var sk: Skeleton3D = ctx.sk
	var anim := Animation.new()
	anim.length = spec.len
	anim.loop_mode = Animation.LOOP_LINEAR if spec.loop else Animation.LOOP_NONE
	var A: Basis = ctx.A
	var keys: Array = spec["keys"]
	# Local rotations and the Body position for every key.
	var rots: Array = []
	var body_pos: Array = []
	var drop: float = spec.get("body_drop", 0.0)
	var hop: float = spec.get("hop", 0.0)
	var root_basis := sk.get_bone_global_rest(sk.get_bone_parent(sk.find_bone("Body"))).basis
	var p0 := _base_pos(ctx, "Body")
	for key in keys:
		var r := {}
		for bone in BONES:
			var e: Array = key[1].get(bone, [0, 0, 0])
			var r_char := Basis.from_euler(Vector3(deg_to_rad(e[0]), deg_to_rad(e[1]), deg_to_rad(e[2])))
			# Character space -> skeleton space -> this bone's own frame.
			var r_skel := Quaternion(A.inverse() * r_char * A)
			var c := _base_global(ctx, bone)
			r[bone] = (_base_rot(ctx, bone) * (c.inverse() * r_skel * c)).normalized()
		rots.append(r)
		var off := Vector3.ZERO
		if drop > 0.0:
			off.y = -drop * clampf(float(key[0]) / 0.12, 0.0, 1.0)
		if hop > 0.0:
			off.y = hop * sin(float(key[0]) / float(spec.len) * PI)
		body_pos.append(p0 + root_basis.inverse() * (ctx.A_inv_full * off))
	for bone in BONES:
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath(ctx.prefix + ":" + bone))
		for k in keys.size():
			anim.rotation_track_insert_key(tr, keys[k][0], rots[k][bone])
	var pt := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pt, NodePath(ctx.prefix + ":Body"))
	for k in keys.size():
		anim.position_track_insert_key(pt, keys[k][0], body_pos[k])
	for foot in FEET:
		var fr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(fr, NodePath(ctx.prefix + ":" + foot))
		var fp := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(fp, NodePath(ctx.prefix + ":" + foot))
		var shin: String = FEET[foot]
		# The foot's rest placement relative to the shin stays fixed.
		var rel := sk.get_bone_global_rest(sk.find_bone(shin)).affine_inverse() * sk.get_bone_global_rest(sk.find_bone(foot))
		for k in keys.size():
			var g_shin := _posed_global(ctx, shin, rots[k], body_pos[k])
			var g_parent := _posed_global(ctx, sk.get_bone_name(sk.get_bone_parent(sk.find_bone(foot))), rots[k], body_pos[k])
			var local := g_parent.affine_inverse() * g_shin * rel
			anim.rotation_track_insert_key(fr, keys[k][0], local.basis.get_rotation_quaternion())
			anim.position_track_insert_key(fp, keys[k][0], local.origin)
	return anim


## A bone's skeleton-space transform for a posed key (forward kinematics).
static func _posed_global(ctx: Dictionary, bone: String, rots: Dictionary, body_pos: Vector3) -> Transform3D:
	var sk: Skeleton3D = ctx.sk
	var i := sk.find_bone(bone)
	var t := Transform3D.IDENTITY
	while i >= 0:
		var name := sk.get_bone_name(i)
		var q: Quaternion = rots[name] if rots.has(name) else _base_rot(ctx, name)
		var p: Vector3 = body_pos if name == "Body" else _base_pos(ctx, name)
		t = Transform3D(Basis(q), p) * t
		i = sk.get_bone_parent(i)
	return t
