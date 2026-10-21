extends Node3D
## Everything that moves, in 3D: Shani on his bike, traffic, crossers,
## pigeons, the warden, Ammi and her chappals. One node per hazard, made
## when the ride starts (never mid-ride), moved to match ride.gd each frame.

const World := preload("res://scripts/world.gd")
const MB := preload("res://scripts/mesh_builder.gd")

var ride
var _nodes := {}             # hazard index -> Node3D
var _bike: Node3D
var _mat := MB.mat(0.7)


func build(r) -> void:
	ride = r
	for c in get_children():
		c.queue_free()
	_nodes.clear()
	for i in ride.hazards.size():
		var o: Dictionary = ride.hazards[i]
		var n := _placeholder(String(o.kind))
		add_child(n)
		_nodes[i] = n
	_bike = _placeholder("bike")
	add_child(_bike)


func _placeholder(kind: String) -> Node3D:
	var mb := MB.new()
	if kind == "bike":
		mb.box(Vector3(0, 0.3, -0.15), Vector3(1.6, 0.9, 0.15), Color(0.85, 0.1, 0.1))
		mb.box(Vector3(0.3, 0.9, -0.2), Vector3(0.7, 1.8, 0.2), Color(0.45, 0.72, 0.95))
	else:
		var k: Dictionary = World.KINDS[kind]
		var h: float = maxf(float(k.h), 0.05)
		mb.box(Vector3(-float(k.len) / 2.0, 0, -float(k.dep) / 2.0), Vector3(float(k.len) / 2.0, h, float(k.dep) / 2.0),
			Color.from_hsv(float(hash(kind) % 100) / 100.0, 0.5, 0.8))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = _mat
	var n := Node3D.new()
	n.add_child(mi)
	return n


func sync(r, _delta: float) -> void:
	if r != ride:
		return
	for i in _nodes:
		var o: Dictionary = ride.hazards[i]
		(_nodes[i] as Node3D).position = Vector3(float(o.x), 0.0, -float(o.d))
	_bike.position = Vector3(float(ride.x), float(ride.h), -float(ride.d))
	_bike.rotation = Vector3(0, 0, deg_to_rad(float(ride.pitch)))
