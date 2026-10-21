extends SceneTree
## Renders Shani on his bike in every pose, side by side, to a PNG, for
## checking poses without playing:
##   godot --path . --script res://tools/rider_viewer.gd -- --out=build/poses.png [--angle] [--kind=125]

const Rider := preload("res://scripts/rider3d.gd")


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var poses := ["ride", "no_hands", "superman", "seat_stand", "selfie"]
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-45, -35, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.82, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	root.add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 10)
	floor_mi.mesh = pm
	root.add_child(floor_mi)
	var riders := []
	for i in poses.size():
		var r := Rider.new()
		r.kind = String(args.get("kind", "70"))
		root.add_child(r)
		riders.append(r)
	await process_frame     # let each rider build itself (_ready)
	for i in poses.size():
		var r = riders[i]
		r.position = Vector3(i * 2.6, 0, 0)
		r.pose(poses[i])
		r.set_motion(0.0, 30.0 if poses[i] in ["no_hands", "selfie"] else 0.0, 0.0, 10.0, 0.3)
	var mid := Vector3((poses.size() - 1) * 1.3 + 0.6, 0.9, 0)
	if args.has("angle"):
		cam.look_at_from_position(mid + Vector3(-2.0, 5.2, 9.0), mid, Vector3.UP)
	else:
		cam.look_at_from_position(mid + Vector3(0, 0.6, 12.5), mid, Vector3.UP)
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(String(args.get("out", "build/poses.png")))
	quit()
