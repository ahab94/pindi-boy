extends RefCounted
## Builds static geometry into one vertex-coloured mesh, so a whole block
## of street (windows, shelves, awnings, poles, tanks...) costs one draw
## call instead of hundreds.
##
## Godot note: SurfaceTool collects vertices (with colour, normal and UV) and
## commit() turns them into an ArrayMesh. A material with
## vertex_color_use_as_albedo paints each face with its vertex colour.
##
## World axes in 3D: X along the road, Y up, Z toward the camera (a road
## depth d becomes z = -d).
##
## Normals point outward; the winding isn't kept consistent, so materials for
## these meshes turn off back-face culling (mat()).

var st := SurfaceTool.new()
var _empty := true


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit() -> ArrayMesh:
	if _empty:
		return null
	return st.commit()


## Shapes here are described counter-clockwise as seen from outside, and
## the normal is worked out from that. Godot's front faces are clockwise, so
## every triangle is emitted reversed (a, c, b).
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, uv_scale := 0.0) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b]:
		st.set_color(col)
		st.set_normal(n)
		if uv_scale > 0.0:
			st.set_uv(_uv(v, n) * uv_scale)
		st.add_vertex(v)
	_empty = false


## A triangle with its own (smooth) vertex normals: emitted clockwise around
## the average normal, whatever order the corners came in.
func _tri_n(p: Array, n: Array, col: Color) -> void:
	var avg: Vector3 = (n[0] + n[1] + n[2])
	var geo: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var order := [0, 2, 1] if geo.dot(avg) > 0.0 else [0, 1, 2]
	for k in order:
		st.set_color(col)
		st.set_normal((n[k] as Vector3).normalized())
		st.add_vertex(p[k])
	_empty = false


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv_scale := 0.0) -> void:
	tri(a, b, c, col, uv_scale)
	tri(a, c, d, col, uv_scale)


## Planar UVs picked by the face direction (walls use x/y, floors x/z).
static func _uv(v: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.7:
		return Vector2(v.x, v.z)
	if absf(n.z) >= absf(n.x):
		return Vector2(v.x, -v.y)
	return Vector2(v.z, -v.y)


## An axis-aligned box from corner p0 to p1. shade darkens the sides a
## little so boxes read even in flat light.
func box(p0: Vector3, p1: Vector3, col: Color, uv_scale := 0.0, faces := 63) -> void:
	var a := Vector3(minf(p0.x, p1.x), minf(p0.y, p1.y), minf(p0.z, p1.z))
	var b := Vector3(maxf(p0.x, p1.x), maxf(p0.y, p1.y), maxf(p0.z, p1.z))
	var x0 := a.x
	var y0 := a.y
	var z0 := a.z
	var x1 := b.x
	var y1 := b.y
	var z1 := b.z
	if faces & 1:   # front (+z, toward the camera)
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col, uv_scale)
	if faces & 2:   # back
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), col, uv_scale)
	if faces & 4:   # top
		quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), col, uv_scale)
	if faces & 8:   # bottom
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), col, uv_scale)
	if faces & 16:  # right (+x)
		quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), col, uv_scale)
	if faces & 32:  # left
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), col, uv_scale)


## A cylinder between two points (poles, wheels, pipes, tanks).
func cylinder(a: Vector3, b: Vector3, r: float, col: Color, sides := 12, caps := true, r_b := -1.0) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis).normalized()
	var rb := r if r_b < 0.0 else r_b
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var o0 := side * cos(a0) + up * sin(a0)
		var o1 := side * cos(a1) + up * sin(a1)
		_smooth_quad(a + o0 * r, a + o1 * r, b + o1 * rb, b + o0 * rb, o0, o1, col)
		if caps:
			_tri_n([a, a + o1 * r, a + o0 * r], [-axis, -axis, -axis], col.darkened(0.1))
			_tri_n([b, b + o0 * rb, b + o1 * rb], [axis, axis, axis], col.darkened(0.1))


func _smooth_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, col: Color) -> void:
	_tri_n([a, b, c], [na, nb, nb], col)
	_tri_n([a, c, d], [na, nb, na], col)


## A sphere-ish blob (tree canopies, heads, fruit).
func sphere(c: Vector3, r: Vector3, col: Color, rings := 6, segs := 10) -> void:
	for i in rings:
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for j in segs:
			var p0 := TAU * j / segs
			var p1 := TAU * (j + 1) / segs
			var v := [_sp(t0, p0), _sp(t0, p1), _sp(t1, p1), _sp(t1, p0)]
			var pts := []
			for q in v:
				pts.append(c + Vector3(q.x * r.x, q.y * r.y, q.z * r.z))
			for k in [[0, 1, 2], [0, 2, 3]]:
				_tri_n([pts[k[0]], pts[k[1]], pts[k[2]]], [v[k[0]], v[k[1]], v[k[2]]], col)
	_empty = false


static func _sp(theta: float, phi: float) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))


## Extrudes a side profile (points in x = along, y = up) across z from z0
## to z1, with a width scale per point (`taper` returns 0..1 of the half
## width at a given x). Used for the rickshaw's shell and hood.
func extrude(profile: Array, zc: float, half: float, taper: Callable, col: Color, side_col = null, cap := true) -> void:
	var n := profile.size()
	var sc: Color = side_col if side_col != null else col
	for i in n:
		var p: Vector2 = profile[i]
		var q: Vector2 = profile[(i + 1) % n]
		var hp: float = half * float(taper.call(p.x))
		var hq: float = half * float(taper.call(q.x))
		quad(Vector3(p.x, p.y, zc + hp), Vector3(q.x, q.y, zc + hq), Vector3(q.x, q.y, zc - hq), Vector3(p.x, p.y, zc - hp), col)
	if cap:
		# Side faces: fan triangulation of the profile (it must be convex-ish
		# or triangulated properly, so use Godot's triangulator).
		var poly := PackedVector2Array()
		for p in profile:
			poly.append(p)
		var tris := Geometry2D.triangulate_polygon(poly)
		for side in [1.0, -1.0]:
			for t in range(0, tris.size(), 3):
				var pts: Array = []
				for k in 3:
					var p: Vector2 = profile[tris[t + k]]
					pts.append(Vector3(p.x, p.y, zc + side * half * float(taper.call(p.x))))
				if side > 0.0:
					tri(pts[0], pts[2], pts[1], sc)
				else:
					tri(pts[0], pts[1], pts[2], sc.darkened(0.2))


## The shared material for builder meshes: vertex colours, both sides.
static func mat(rough := 0.85, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = rough
	if tex:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
