extends SceneTree
## Taps the on-screen touch buttons with real screen-touch events and checks
## the bike responds: auto throttle, the wheelie, a trick, the pause button.
##   godot --headless --path . --script res://tests/touch_test.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = false
	root.add_child(game)
	_run.call_deferred(game)


func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	# Real touches arrive in window pixels; Godot maps them into the game's
	# 1280x720 (or 720x1280) space. So send the window position of `pos`.
	e.position = root.get_final_transform() * pos
	e.pressed = down
	Input.parse_input_event(e)


## Every ride (most buttons, in the air and in SCENE ON too), on phone and
## tablet shapes: no two buttons may overlap, and all stay on screen.
func _no_overlaps(game) -> void:
	var levels = load("res://scripts/levels.gd")
	var sizes := [Vector2(720, 1280), Vector2(720, 1560), Vector2(720, 1100), Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960)]
	for i in levels.count():
		game.start_level(i)
		for air in [false, true]:
			game.ride.airborne = air
			game.ride.scene_t = 5.0 if air else 0.0
			for sz in sizes:
				var b: Array = game.hud.layout_buttons(sz)
				var has_tricks: bool = game.ride.unlocked.size() > 0 or game.ride.level.get("pop", false)
				var wanted: int = 4 + (1 if "jump" in game.ride.moves else 0) + 1 + (1 if has_tricks else 0)
				check(b.size() == wanted, "ride %d %s: all %d buttons placed (got %d)" % [i + 1, sz, wanted, b.size()])
				for p in b.size():
					var a: Array = b[p]
					var c: Vector2 = a[1]
					check(c.x - float(a[2]) >= 0.0 and c.x + float(a[2]) <= sz.x and c.y + float(a[2]) <= sz.y, "ride %d %s: %s on screen" % [i + 1, sz, a[0]])
					for q in range(p + 1, b.size()):
						var o: Array = b[q]
						check(c.distance_to(o[1]) >= float(a[2]) + float(o[2]), "ride %d %s: %s and %s overlap" % [i + 1, sz, a[0], o[0]])
		game.ride.airborne = false
		game.ride.scene_t = 0.0


func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	Input.parse_input_event(e)


func _find(game, action: String) -> Vector2:
	for b in game.hud._buttons:
		if b[0] == action:
			return b[1]
	return Vector2(-1, -1)


func _run(game) -> void:
	await process_frame
	game.hud.show_touch = true
	game.start_level(4)
	game.ride.t = 0.0
	for f in 30:
		await physics_frame
	await process_frame
	check(_find(game, "wheelie").x > 0.0, "the wheelie button is on screen")
	var v0: float = game.ride.v
	for f in 150:
		await physics_frame
	check(game.ride.v > 9.0, "touch screens get an automatic throttle (v %.1f, from %.1f)" % [game.ride.v, v0])
	_touch(0, _find(game, "wheelie"), true)
	var peak := 0.0
	for f in 50:
		await physics_frame
		peak = maxf(peak, game.ride.pitch)
	check(peak > 15.0, "holding WHEELIE lifts the front (peak %.0f)" % peak)
	# The quick selector: hold TRICK, slide to NO HANDS, let go.
	var tb := _find(game, "trick_btn")
	check(tb.x > 0.0, "the TRICK button is on screen")
	_touch(1, tb, true)
	await process_frame
	var target := Vector2.ZERO
	for it in game.hud.trick_fan(tb):
		if it[0] == "trick_1":
			target = it[1]
	check(target != Vector2.ZERO, "NO HANDS is in the selector")
	_drag(1, target)
	for f in 3:
		await physics_frame
	check(game.ride.trick == "no_hands" or game.ride.tricks_done > 0, "sliding to NO HANDS mid-wheelie does the trick")
	_touch(1, target, false)
	for f in 50:
		await physics_frame
	# A quick tap repeats it.
	var done_before: int = game.ride.tricks_done
	_touch(1, tb, true)
	await physics_frame
	_touch(1, tb, false)
	for f in 50:
		await physics_frame
	check(game.ride.tricks_done > done_before or game.ride.trick != "", "a quick tap on TRICK repeats the last trick")
	_touch(0, _find(game, "wheelie"), false)
	for f in 5:
		await physics_frame
	check(not Input.is_action_pressed("wheelie"), "letting go releases the wheelie")
	# JUMP: hold, let go, fly.
	for f in 40:
		await physics_frame
	var jp := _find(game, "jump")
	check(jp.x > 0.0, "the JUMP button is on screen")
	_touch(3, jp, true)
	for f in 25:
		await physics_frame
	_touch(3, jp, false)
	var flew := false
	for f in 20:
		await physics_frame
		flew = flew or game.ride.airborne
	check(flew, "holding and letting go of JUMP hops")
	for f in 90:
		await physics_frame
	_touch(2, _find(game, "menu_btn"), true)
	await process_frame
	await process_frame
	check(game.state == game.State.MENU, "the pause button goes back to the menu")
	_no_overlaps(game)
	print("TOUCH OK" if fails == 0 else "TOUCH FAILED (%d)" % fails)
	quit(1 if fails else 0)
