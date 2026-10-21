extends Node3D
## The ride in 3D. The rules still live in ride.gd and are untouched: this
## node reads the ride every frame and places a 3D street, vehicles, people
## and Shani to match, then looks at it with a camera from the near
## footpath, a little above and behind, so a wheelie still reads in profile.
##
## Godot notes:
## - A Camera3D marked current decides what the 3D world looks like on
##   screen; the HUD (a CanvasLayer) draws on top.
## - WorldEnvironment sets the sky, ambient light, fog and glow;
##   DirectionalLight3D is the sun, with shadows.
## - Axes: X along the road, Y up, Z toward the camera (road depth d -> -d).

const World := preload("res://scripts/world.gd")
const Ride := preload("res://scripts/ride.gd")
const Street := preload("res://scripts/street3d.gd")
const Actors := preload("res://scripts/actors3d.gd")
const Overlay := preload("res://scripts/overlay3d.gd")

const SKIES := {
	# sky top, horizon, sun colour, sun energy, ambient, sun pitch (deg)
	"morning": [Color(0.42, 0.66, 0.95), Color(0.98, 0.88, 0.74), Color(1.0, 0.94, 0.82), 1.25, 0.55, -38.0],
	"noon": [Color(0.32, 0.58, 0.95), Color(0.82, 0.9, 0.98), Color(1, 1, 0.97), 1.35, 0.6, -60.0],
	"golden": [Color(0.42, 0.52, 0.85), Color(1.0, 0.74, 0.46), Color(1.0, 0.8, 0.55), 1.3, 0.5, -24.0],
	"rain": [Color(0.42, 0.46, 0.52), Color(0.66, 0.69, 0.74), Color(0.82, 0.85, 0.9), 0.55, 0.7, -55.0],
	"dusk": [Color(0.3, 0.24, 0.52), Color(0.98, 0.56, 0.42), Color(1.0, 0.62, 0.45), 0.95, 0.5, -16.0],
	"evening": [Color(0.12, 0.12, 0.3), Color(0.8, 0.44, 0.38), Color(0.95, 0.55, 0.45), 0.6, 0.45, -12.0],
}

var ride
var zoom := 1.0
var portrait := false
var camera: Camera3D
var _street: Street
var _actors: Actors
var _overlay: Overlay
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _built_for = null
var _cam_x := -999.0
var _cam_lift := 0.0
var shake := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 38.0
	camera.far = 260.0
	add_child(camera)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	# Two cascades: sharp near Shani, coarser up the road.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 55.0
	_sun.shadow_blur = 1.5
	_sun.shadow_bias = 0.04
	add_child(_sun)
	_env = WorldEnvironment.new()
	_env.environment = Environment.new()
	add_child(_env)
	_street = Street.new()
	add_child(_street)
	_actors = Actors.new()
	add_child(_actors)
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_overlay = Overlay.new()
	_overlay.view = self
	layer.add_child(_overlay)


func reset() -> void:
	_cam_x = -999.0
	shake = 0.0


func _process(delta: float) -> void:
	if ride == null:
		return
	if _built_for != ride:
		_build()
	var size := get_viewport().get_visible_rect().size
	portrait = size.y > size.x
	_actors.sync(ride, delta)
	_follow_camera(delta)
	_overlay.ride = ride
	_overlay.queue_redraw()


func _build() -> void:
	_built_for = ride
	var sky: Array = SKIES.get(String(ride.level.get("sky", "noon")), SKIES.noon)
	var env := _env.environment
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = sky[0]
	sm.sky_horizon_color = sky[1]
	sm.ground_horizon_color = sky[1]
	sm.ground_bottom_color = (sky[1] as Color).darkened(0.4)
	sm.sun_angle_max = 20.0
	var s := Sky.new()
	s.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(sky[4]) * 0.55
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_color = Color(0.95, 0.9, 0.85)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_light_color = sky[1]
	env.fog_density = 0.0012 if ride.level.sky != "rain" else 0.008
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	_sun.light_color = sky[2]
	_sun.light_energy = float(sky[3]) * 0.8
	# The sun stands behind the camera and to the right, so shop fronts
	# (which face the camera) are lit and shadows fall away up the road.
	_sun.rotation_degrees = Vector3(float(sky[5]), -35.0, 0.0)
	_street.build(ride, Color(1, 1, 1))
	_actors.build(ride)


## The camera trails Shani along the road: it sits over the near footpath,
## a bit behind him, and aims ahead so you see what's coming. In the air it
## rises with him.
func _follow_camera(delta: float) -> void:
	var x: float = ride.x
	var d: float = ride.d
	var lead := clampf(float(ride.v), 0.0, 20.0) * 0.18
	if _cam_x < -900.0:
		_cam_x = x
	_cam_x = lerpf(_cam_x, x + lead, minf(1.0, delta * 5.0))
	_cam_lift = lerpf(_cam_lift, maxf(0.0, float(ride.h) - 0.5) * 0.6, minf(1.0, delta * 4.0))
	var back := 10.5 / zoom
	var high := 7.2 / zoom
	var ahead := 4.5
	if portrait:
		camera.fov = 62.0
		back = 11.0 / zoom
		high = 7.0 / zoom
		ahead = 2.0
	else:
		camera.fov = 36.0
	var target := Vector3(_cam_x + ahead, 0.9 + _cam_lift, -d * 0.3 - 4.0)
	var pos := Vector3(_cam_x + ahead - 2.0, high + _cam_lift, back)
	if shake > 0.0:
		pos += Vector3(sin(ride.t * 70.0), cos(ride.t * 63.0), 0.0) * shake * 0.01
		shake = maxf(0.0, shake - delta * 30.0)
	camera.position = pos
	camera.look_at(target, Vector3.UP)


## World point (x along, d across, h up) on screen, for the 2D overlay.
func screen(x: float, d: float, h: float) -> Vector2:
	return camera.unproject_position(Vector3(x, h, -d))


func behind_camera(x: float, d: float, h: float) -> bool:
	return camera.is_position_behind(Vector3(x, h, -d))
