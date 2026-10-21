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
	var trick_pos := _find(game, "trick_1")
	check(trick_pos.x > 0.0, "the no-hands button is on screen")
	_touch(1, trick_pos, true)
	for f in 3:
		await physics_frame
	_touch(1, trick_pos, false)
	for f in 3:
		await physics_frame
	check(game.ride.trick == "no_hands" or game.ride.tricks_done > 0, "tapping NO HANDS mid-wheelie does the trick")
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
	print("TOUCH OK" if fails == 0 else "TOUCH FAILED (%d)" % fails)
	quit(1 if fails else 0)
