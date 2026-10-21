extends Node3D
## Shani on his bike (or the warden on his), in 3D. The node's origin is the
## rear tyre's contact patch; it faces +X. A wheelie is the whole node
## turning about Z (nose up). The bike is built from parts with
## mesh_builder.gd; the wheels are their own nodes so they can spin.

const MB := preload("res://scripts/mesh_builder.gd")
const Person := preload("res://scripts/person3d.gd")

const R := 0.31               # wheel radius
const CHROME := Color(0.82, 0.84, 0.88)
const TYRE := Color(0.08, 0.08, 0.09)

var kind := "70"              # "70", "125", "warden"
var rider_role := "shani"
var person: Person
var _wheels: Array = []
var _body: Node3D             # everything that tilts with a wheelie
var _rider_pivot: Node3D
var _blur_mat: StandardMaterial3D


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = _frame_mesh()
	mi.material_override = MB.mat(0.45)
	_body.add_child(mi)
	var big := 1.06 if kind == "125" else 1.0
	for wx in [0.0, 1.28 * big]:
		var w := MeshInstance3D.new()
		w.mesh = _wheel_mesh(R * big)
		w.material_override = MB.mat(0.5)
		w.position = Vector3(wx, R * big, 0)
		_body.add_child(w)
		_wheels.append(w)
	_rider_pivot = Node3D.new()
	_body.add_child(_rider_pivot)
	person = Person.new()
	person.role = rider_role
	person.height = 0.9
	_rider_pivot.add_child(person)
	pose("ride")


## Places the rider for a pose (where the hips sit relative to the seat).
func pose(name: String) -> void:
	var off := Vector3(0.18, 0.08, 0.0)
	match name:
		"seat_stand":
			off = Vector3(0.22, 0.74, 0.0)
		"superman":
			off = Vector3(-0.05, 0.3, 0.0)
		"no_hands":
			off = Vector3(0.16, 0.08, 0.0)
	_rider_pivot.position = off
	person.play(name)


## Every frame: wheel spin from distance travelled, wheelie angle, wobble.
func set_motion(x: float, pitch_deg: float, wobble: float, speed: float, t: float) -> void:
	for w in _wheels:
		(w as Node3D).rotation.z = -x / R
	rotation.z = deg_to_rad(pitch_deg) + wobble
	person.flutter(t, speed)


func _frame_mesh() -> ArrayMesh:
	var mb := MB.new()
	var body := Color(0.82, 0.08, 0.08)
	var tank := body
	var stripe := Color(1, 1, 1)
	if kind == "125":
		body = Color(0.1, 0.1, 0.12)
		tank = Color(0.12, 0.12, 0.14)
		stripe = Color(0.9, 0.1, 0.1)
	elif kind == "warden":
		body = Color(0.95, 0.95, 0.97)
		tank = Color(0.12, 0.3, 0.7)
		stripe = Color(0.12, 0.3, 0.7)
	var big := 1.06 if kind == "125" else 1.0
	var fx := 1.28 * big
	var black := Color(0.07, 0.07, 0.08)
	# Silencer with its heat shield, angled up at the back: the pataakha.
	mb.cylinder(Vector3(0.82, 0.27, 0.13), Vector3(0.28, 0.33, 0.17), 0.035, CHROME.darkened(0.15), 8)
	mb.cylinder(Vector3(0.3, 0.33, 0.17), Vector3(-0.32, 0.42, 0.17), 0.075, CHROME, 12)
	mb.cylinder(Vector3(-0.32, 0.42, 0.17), Vector3(-0.4, 0.435, 0.17), 0.06, CHROME.darkened(0.4), 12)
	mb.box(Vector3(-0.05, 0.37, 0.24), Vector3(0.25, 0.46, 0.255), Color(0.22, 0.22, 0.24))
	# Swingarm, chain case, shocks.
	mb.box(Vector3(0.0, R - 0.03, -0.1), Vector3(0.6, R + 0.03, -0.08), Color(0.15, 0.15, 0.17))
	mb.box(Vector3(0.0, R - 0.03, 0.08), Vector3(0.6, R + 0.03, 0.1), Color(0.15, 0.15, 0.17))
	if kind != "125":
		mb.box(Vector3(-0.1, R - 0.06, 0.1), Vector3(0.66, R + 0.1, 0.13), black)
	for side in [-0.1, 0.1]:
		mb.cylinder(Vector3(0.04, R + 0.04, side), Vector3(0.12, 0.7, side), 0.025, CHROME, 6)
		mb.cylinder(Vector3(0.05, R + 0.12, side), Vector3(0.1, 0.55, side), 0.04, Color(0.85, 0.2, 0.15) if kind != "warden" else Color(0.2, 0.3, 0.8), 8)
	# Engine: finned cylinder, crankcase cover, kick lever, footpegs.
	mb.box(Vector3(0.5, 0.18, -0.13), Vector3(0.95, 0.52, 0.13), Color(0.45, 0.45, 0.47))
	for i in 5:
		mb.box(Vector3(0.74, 0.28 + i * 0.05, -0.15), Vector3(1.0, 0.3 + i * 0.05, 0.15), Color(0.6, 0.6, 0.62))
	mb.cylinder(Vector3(0.62, 0.32, 0.13), Vector3(0.62, 0.32, 0.17), 0.12, Color(0.72, 0.72, 0.75), 16)
	mb.cylinder(Vector3(0.45, 0.38, 0.17), Vector3(0.3, 0.28, 0.2), 0.02, Color(0.25, 0.25, 0.25), 6)
	mb.cylinder(Vector3(0.62, 0.14, -0.24), Vector3(0.62, 0.14, 0.24), 0.025, black, 6)
	# Frame tube under the tank.
	mb.cylinder(Vector3(0.58, 0.55, 0.0), Vector3(1.06 * big, 0.92, 0.0), 0.045, body.darkened(0.25), 8)
	# Rear mudguard, carrier, tail light, number plate.
	mb.box(Vector3(-0.42, 0.45, -0.07), Vector3(0.22, 0.6, 0.07), body)
	mb.box(Vector3(-0.2, 0.7, -0.12), Vector3(0.3, 0.73, 0.12), CHROME)
	mb.box(Vector3(-0.44, 0.47, -0.05), Vector3(-0.38, 0.54, 0.05), Color(1, 0.12, 0.08))
	mb.box(Vector3(-0.5, 0.27, -0.09), Vector3(-0.47, 0.41, 0.09), Color(0.97, 0.97, 0.92))
	# Side covers with the number.
	mb.box(Vector3(0.24, 0.47, -0.12), Vector3(0.62, 0.71, 0.12), body)
	# Seat with stitching, and the tank with its stripe and cap.
	mb.box(Vector3(-0.02, 0.66, -0.13), Vector3(0.66, 0.8, 0.13), Color(0.09, 0.08, 0.08))
	mb.box(Vector3(0.04, 0.8, -0.1), Vector3(0.6, 0.82, 0.1), Color(0.14, 0.13, 0.13))
	mb.sphere(Vector3(0.84, 0.77, 0.0), Vector3(0.25, 0.1, 0.15), tank, 6, 12)
	mb.box(Vector3(0.66, 0.74, -0.155), Vector3(1.0, 0.77, 0.155), stripe)
	mb.cylinder(Vector3(0.84, 0.86, 0.0), Vector3(0.84, 0.88, 0.0), 0.035, CHROME, 10)
	# Fork, front mudguard, headlight, speedo, handlebar with grips, mirror.
	for side in [-0.08, 0.08]:
		mb.cylinder(Vector3(fx, R, side), Vector3(1.08 * big, 1.0, side), 0.028, CHROME, 8)
		mb.cylinder(Vector3(fx - 0.02, R + 0.12, side), Vector3(fx - 0.06, R + 0.38, side), 0.04, black, 8)
	mb.box(Vector3(fx - 0.25, R + 0.26, -0.07), Vector3(fx + 0.3, R + 0.32, 0.07), body)
	mb.cylinder(Vector3(1.16 * big, 0.88, 0.0), Vector3(1.28 * big, 0.88, 0.0), 0.11, CHROME, 14)
	mb.cylinder(Vector3(1.28 * big, 0.88, 0.0), Vector3(1.29 * big, 0.88, 0.0), 0.085, Color(1.0, 0.96, 0.78), 14)
	mb.cylinder(Vector3(1.06, 0.99, 0.0), Vector3(1.1, 1.02, 0.0), 0.06, black, 10)
	mb.cylinder(Vector3(1.04, 1.04, -0.36), Vector3(1.04, 1.04, 0.36), 0.018, CHROME, 6)
	for side in [-1.0, 1.0]:
		mb.cylinder(Vector3(1.04, 1.04, 0.3 * side), Vector3(1.03, 1.04, 0.4 * side), 0.03, black, 8)
		mb.cylinder(Vector3(1.06, 1.04, 0.22 * side), Vector3(1.0, 1.3, 0.24 * side), 0.012, CHROME, 5)
		mb.sphere(Vector3(1.0, 1.33, 0.24 * side), Vector3(0.07, 0.05, 0.02), CHROME, 4, 8)
		mb.sphere(Vector3(1.18, 0.95, 0.12 * side), Vector3(0.03, 0.02, 0.02), Color(1, 0.6, 0.1), 3, 6)
	if kind != "warden":
		# The helmet: on the mirror, never on the head.
		mb.sphere(Vector3(1.0, 1.0, 0.3), Vector3(0.13, 0.12, 0.13), Color(0.98, 0.82, 0.1), 6, 12)
		mb.box(Vector3(1.06, 0.95, 0.23), Vector3(1.12, 1.05, 0.37), Color(0.15, 0.2, 0.3))
	else:
		mb.box(Vector3(-0.15, 0.74, -0.06), Vector3(-0.05, 0.86, 0.06), Color(0.15, 0.3, 1.0))
	return mb.commit()


func _wheel_mesh(r: float) -> ArrayMesh:
	var mb := MB.new()
	mb.cylinder(Vector3(0, 0, -0.05), Vector3(0, 0, 0.05), r, TYRE, 24)
	mb.cylinder(Vector3(0, 0, -0.052), Vector3(0, 0, 0.052), r * 0.78, Color(0.18, 0.18, 0.2), 24)
	mb.cylinder(Vector3(0, 0, -0.054), Vector3(0, 0, 0.054), r * 0.7, Color(0.55, 0.56, 0.6), 24)
	for i in 12:
		var a := TAU * i / 12.0
		mb.cylinder(Vector3(0, 0, 0.0), Vector3(cos(a) * r * 0.7, sin(a) * r * 0.7, 0.04 * (1 if i % 2 == 0 else -1)), 0.006, CHROME, 4, false)
	mb.cylinder(Vector3(0, 0, -0.07), Vector3(0, 0, 0.07), r * 0.18, CHROME, 12)
	# Tread blocks so the spin shows.
	for i in 18:
		var a := TAU * i / 18.0
		mb.box(Vector3(cos(a) * r - 0.015, sin(a) * r - 0.015, -0.055), Vector3(cos(a) * r + 0.015, sin(a) * r + 0.015, 0.055), Color(0.14, 0.14, 0.15))
	return mb.commit()
