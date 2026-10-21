extends SceneTree
## Checks the level data and each mechanic on ride.gd directly, with
## scripted input and no window.
##   godot --headless --path . --script res://tests/game_test.gd

const Levels := preload("res://scripts/levels.gd")
const Ride := preload("res://scripts/ride.gd")
const World := preload("res://scripts/world.gd")

var fails := 0


func _initialize() -> void:
	_levels()
	_wheelie()
	_loop_out()
	_breaker_air()
	_trick_bail()
	_combo_bank()
	_variety()
	_crash_and_keys()
	_pothole()
	_pataakha()
	_jump_over()
	_warden()
	_chappal()
	_same_street()
	print("GAME OK" if fails == 0 else "GAME FAILED (%d)" % fails)
	quit(1 if fails else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func ride_on(level: Dictionary) -> Ride:
	var r := Ride.new()
	r.setup(level)
	r.t = 0.0
	return r


## A bare street with nothing on it, plus whatever's given.
func bare(extra := {}) -> Dictionary:
	var lvl := {"name": "test", "tip": "", "bike": "70", "length": 400, "target": 100, "tricks": ["no_hands", "superman"],
		"scatter": {}, "sky": "noon", "seed": 1, "win": ""}
	lvl.merge(extra, true)
	return lvl


func run(r: Ride, seconds: float, input: Dictionary) -> void:
	for i in int(seconds * 60.0):
		r.step(1.0 / 60.0, input)


func _levels() -> void:
	check(Levels.count() == 10, "ten rides")
	var tricks_seen := 0
	for i in Levels.count():
		var l: Dictionary = Levels.get_level(i)
		for key in ["name", "tip", "bike", "length", "target", "tricks", "scatter", "sky", "seed", "win"]:
			check(l.has(key), "ride %d has %s" % [i, key])
		check(l.tricks.size() >= tricks_seen, "tricks never get taken away (ride %d)" % i)
		tricks_seen = l.tricks.size()
		for k in l.scatter:
			check(World.KINDS.has(k), "ride %d: known kind %s" % [i, k])
		var w := World.build(l)
		check(w.hazards.size() > 0, "ride %d has hazards" % i)


func _wheelie() -> void:
	var r := ride_on(bare())
	run(r, 1.0, {"gas": true})
	var aim := 45.0
	var peak := 0.0
	for i in 180:
		r.step(1.0 / 60.0, {"gas": true, "lift": r.pitch + r.pitch_v * 0.22 < aim})
		peak = maxf(peak, r.pitch)
	check(r.pitch > 25.0 and r.pitch < 70.0, "feathering holds a wheelie (pitch %.0f)" % r.pitch)
	check(r.crash_t == 0.0, "no crash while feathering")
	check(r.pot > 0.0 and "WHEELIE" in r.chain, "a held wheelie scores")
	check(r.v <= float(r.bike.wheelie_top) + 0.5, "wheelies are slower than flat out")
	run(r, 2.5, {"gas": true})
	check(r.pitch == 0.0, "letting go drops the front")
	check(r.pot == 0.0 and r.views > 0, "the combo banks after landing the front (views %d)" % r.views)


func _loop_out() -> void:
	var r := ride_on(bare())
	run(r, 1.0, {"gas": true})
	run(r, 2.0, {"gas": true, "lift": true})
	check(r.pitch > 30.0 and r.pitch < 60.0 and r.crashes == 0, "holding WHEELIE holds a steady wheelie (pitch %.0f)" % r.pitch)
	run(r, 7.0, {"gas": true, "lift": true})
	check(r.crashes == 1 and r.crash_cause == "looped", "holding it far too long still loops it")
	check(r.views == Ride.FAIL_VIEWS, "a fail is still worth a few views")


func _breaker_air() -> void:
	var r := ride_on(bare({"placed": [[60.0, "breaker", 1]]}))
	var flew := false
	var air := 0.0
	for i in 600:
		r.step(1.0 / 60.0, {"gas": true})
		if r.airborne:
			flew = true
			air += 1.0 / 60.0
	check(flew, "a speed breaker launches the bike")
	check(air > 0.4, "breaker air lasts long enough for a no-hands (%.2fs)" % air)
	check("BREAKER AIR" in r.chain or r.views > 0, "air scores")


func _trick_bail() -> void:
	# A superman (0.9 s) off a speed breaker (~0.6 s of air) can't finish.
	var r := ride_on(bare({"placed": [[60.0, "breaker", 1]]}))
	var pressed := false
	for i in 600:
		var inp := {"gas": true}
		if r.airborne and not pressed:
			inp.trick = "superman"
			pressed = true
		r.step(1.0 / 60.0, inp)
	check(r.crashes == 0, "a trick too big for the air never crashes you")
	check(r.events.any(func(e) -> bool: return String(e[1]).begins_with("too_low") or e[1] == "sloppy"), "it's refused (TOO LOW) or a sloppy landing")
	# Locked tricks do nothing.
	var r2 := ride_on(bare({"placed": [[60.0, "breaker", 1]], "tricks": []}))
	for i in 600:
		r2.step(1.0 / 60.0, {"gas": true, "trick": "no_hands" if r2.airborne else ""})
	check(r2.tricks_done == 0 and r2.crashes == 0, "locked tricks can't be done")


func _combo_bank() -> void:
	var r := ride_on(bare())
	r._element("A", 100)
	r._element("B", 100)
	check(r.mult == 2 and r.pot == 200.0, "elements add to the pot and the multiplier")
	r._bank()
	check(r.views == 400, "banking pays pot x multiplier (%d)" % r.views)
	r._element("A", 100)
	r._crash("cart")
	check(r.pot == 0.0 and r.views == 400 + Ride.FAIL_VIEWS, "a crash loses the combo")


func _variety() -> void:
	var r := ride_on(bare())
	r._element("NO HANDS", 100)
	r._element("NO HANDS", 100)
	r._element("NO HANDS", 100)
	check(r.mult == 1, "repeats don't raise the multiplier")
	check(is_equal_approx(r.pot, 175.0), "repeats are worth half each time (%.0f)" % r.pot)


func _crash_and_keys() -> void:
	var r := ride_on(bare())
	run(r, 1.0, {"gas": true})
	for i in Ride.PATIENCE:
		r._crash("cart")
		run(r, Ride.CRASH_TIME + 0.1, {"gas": true})
		if i < Ride.PATIENCE - 1:
			check(r.result == "" and r.safe_t > 0.0, "back on the bike after crash %d, briefly safe" % (i + 1))
	check(r.result == "keys", "three crashes and Abbu takes the keys (%s, %d)" % [r.result, r.crashes])


func _pothole() -> void:
	var r := ride_on(bare({"placed": [[50.0, "pothole", 1]]}))
	r.d = World.LANES[1]
	r._element("X", 100)
	run(r, 6.0, {"gas": true})
	check(r.events.any(func(e) -> bool: return e[1] == "pothole"), "a pothole on two wheels jolts")
	var r2 := ride_on(bare({"placed": [[50.0, "pothole", 1]]}))
	r2.d = World.LANES[1]
	for i in 600:
		r2.step(1.0 / 60.0, {"gas": true, "lift": r2.x > 35.0 and r2.pitch + r2.pitch_v * 0.22 < 40.0})
	check(r2.events.all(func(e) -> bool: return e[1] != "pothole"), "a wheelie skips the pothole")


func _pataakha() -> void:
	var r := ride_on(bare({"pop": true, "placed": [[18.0, "pigeons", 0]]}))
	run(r, 1.0, {"gas": true})
	r.step(1.0 / 60.0, {"gas": true, "pop": true})
	var pig: Dictionary = r.hazards.filter(func(h) -> bool: return h.kind == "pigeons")[0]
	check(pig.state == "fly", "pataakha scatters pigeons")
	check(r.pop_t > 0.0, "pataakha has a cooldown")
	var r2 := ride_on(bare({"placed": [[18.0, "pigeons", 0]]}))
	run(r2, 1.0, {"gas": true})
	r2.step(1.0 / 60.0, {"gas": true, "pop": true})
	check(r2.pop_t == 0.0, "no pataakha before the silencer is tuned")


func _jump_over() -> void:
	var r := ride_on(bare({"placed": [[60.0, "ramp", 1], [68.0, "cart", 1]]}))
	r.d = World.LANES[1]
	run(r, 8.0, {"gas": true})
	check(r.crashes == 0, "the ramp clears the thela (crashes %d)" % r.crashes)
	check(r.events.any(func(e) -> bool: return String(e[1]) == "over cart"), "jumping a thela scores")


func _warden() -> void:
	var r := ride_on(bare({"warden": true}))
	# Dawdle: brake hard and let him catch up.
	run(r, 12.0, {"brake": true})
	check(r.events.any(func(e) -> bool: return e[1] == "chalaan"), "a dawdler gets a chalaan")
	var r2 := ride_on(bare({"warden": true, "length": 300}))
	run(r2, 40.0, {"gas": true})
	check(r2.events.all(func(e) -> bool: return e[1] != "chalaan"), "flat out outruns the warden")


func _chappal() -> void:
	var r := ride_on(bare({"chappals": true, "length": 600}))
	run(r, 12.0, {"gas": false})
	check(r.events.any(func(e) -> bool: return e[1] == "chappal"), "sitting still gets you chappal'd")
	check(r.chappals.size() > 0, "Ammi throws")


func _same_street() -> void:
	var a := World.build(Levels.get_level(5))
	var b := World.build(Levels.get_level(5))
	var same: bool = a.hazards.size() == b.hazards.size()
	for i in mini(a.hazards.size(), b.hazards.size()):
		same = same and a.hazards[i].kind == b.hazards[i].kind and is_equal_approx(a.hazards[i].x, b.hazards[i].x)
	check(same, "the same seed builds the same street")
