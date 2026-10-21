extends RefCounted
## All the rules of a ride: the bike's physics (speed, lanes, wheelie
## balance, air), tricks, the combo, crashes, traffic, crossers, pigeons,
## the warden and Ammi's chappals.
##
## It knows nothing about drawing or sound. game.gd feeds it input every
## physics tick (60 per second) and reads `events`, which view.gd, hud.gd and
## sound.gd turn into pictures and noise. Same input, same ride: that's what
## lets the autopilot prove every level can be passed.

const World := preload("res://scripts/world.gd")

const COUNTDOWN := 3.0
const GRAVITY := 14.0          # a bit floaty on purpose: airtime is the fun part
const LOOP_OUT := 95.0         # past this the bike flips over backwards
const SWEET := Vector2(30, 65) # the wheelie angles that score double
const LAT_ACCEL := 14.0
const WOBBLE_GROWTH := 30.0    # deg/s^2 of extra squirm per second of wheelie
const WHEELIE_RATE := 40.0     # views per second on the back wheel (double in the green)
const CHAIN_GRACE := 1.0       # seconds on two wheels before the combo is banked
const MAX_MULT := 10
const PATIENCE := 3            # crashes before Abbu takes the keys
const FAIL_VIEWS := 100        # people do love a fail video
const CRASH_TIME := 2.4
const SAFE_TIME := 1.6         # after a crash you ride through things for a moment
const ACTIVATE := 50.0         # traffic starts moving when this close
const POP_COOLDOWN := 1.2
const POP_RANGE := 15.0
const CHAPPAL_EVERY := 2.4
const CHAPPAL_FLIGHT := 1.25
const AMMI_D := World.FAR_WALK - 0.7   # Ammi stands on the shop awnings
const AMMI_H := 2.6

## The two bikes. top: flat-out speed; wheelie_top: the most you can do on
## the back wheel; lift: how hard the throttle pulls the front up (deg/s^2);
## grav: how hard the bike falls back; damp: steadiness; launch: air.
const BIKES := {
	"70": {"name": "THE 70", "cruise": 8.0, "top": 15.0, "wheelie_top": 11.5, "accel": 4.5,
		"lift": 330.0, "grav": 300.0, "damp": 1.5, "launch": 1.0, "lane": 3.6, "balance": 80.0, "squirm": 1.0},
	"125": {"name": "THE 125", "cruise": 9.5, "top": 19.0, "wheelie_top": 14.5, "accel": 6.0,
		"lift": 335.0, "grav": 300.0, "damp": 2.6, "launch": 1.12, "lane": 4.0, "balance": 80.0, "squirm": 0.8},
}

## time: how long it takes (it must finish before you land); steer: whether
## you can still steer while doing it.
const TRICKS := {
	"no_hands": {"label": "NO HANDS", "time": 0.55, "views": 150, "steer": false, "key": "J"},
	"superman": {"label": "SUPERMAN", "time": 0.9, "views": 400, "steer": false, "key": "K"},
	"seat_stand": {"label": "SEAT STAND", "time": 1.2, "views": 650, "steer": false, "key": "L"},
	"selfie": {"label": "SELFIE", "time": 0.8, "views": 300, "steer": true, "key": "U"},
}

const CRASH_LINES := {
	"cart": "FRUIT EVERYWHERE", "eggs": "OMELETTE!", "rickshaw": "RICKSHAW 1, SHANI 0",
	"wrongway": "HE WAS ON THE WRONG SIDE!", "wagon": "WAGON WINS", "bus": "THE BUS DIDN'T EVEN NOTICE",
	"baraat": "GATECRASHED THE BARAAT", "ped": "SORRY UNCLE!", "goats": "BAKRI 1, SHANI 0",
	"looped": "LOOPED IT!", "bailed": "BAILED!", "backflop": "ACCIDENTAL BACKFLIP", "faceplant": "FACE PLANT",
}
const PRAISE := ["WAH PAI!", "OYE HOYE!", "SCENE ON HAI!", "KAMAAL!", "JIGAR!", "PINDI BOYS!", "UFF!", "VIRAL!"]
const LAUGH := ["HAHAHA!", "OYE HOYE!", "PAGAL HAI?", "HELMET KAHAN HAI?", "AMMI KO BATAUN?", "BACH KE!"]
const UNCLE := ["OYE!", "TAMEEZ!", "AARAM SE!", "BADTAMEEZ!", "MERI DAWAI!"]
const AMMI := ["SHANIII!", "GHAR AAO ZARA!", "YEH LO!", "DAWAI KAHAN HAI?", "AAJ BATATI HOON!"]

var level: Dictionary
var bike: Dictionary
var length := 500.0
var t := -COUNTDOWN
var result := ""             # "", "finished", "keys"
var events: Array = []       # [time, "name args"], read by the view, the HUD and sound
var popups: Array = []       # floating text in the world
var bubbles: Array = []      # speech bubbles: {x, d, h, text, t0}

var hazards: Array = []
var buildings: Array = []
var poles: Array = []
var crowd: Array = []
var trees: Array = []
var chappals: Array = []
var warden := {}             # empty when there's no warden on this ride
var ammi_x := -100.0

# The bike. x is the rear wheel's contact point.
var x := 0.0
var d := 4.5
var v := 0.0
var vd := 0.0
var h := 0.0
var vh := 0.0
var pitch := 0.0             # wheelie angle, degrees
var pitch_v := 0.0
var airborne := false
var air_time := 0.0
var trick := ""
var trick_t := 0.0
var crash_t := 0.0
var crash_cause := ""
var crash_v := 0.0           # how fast it was going when it crashed (the tumble)
var safe_t := 0.0
var skid_t := 0.0
var skid_dir := 1.0
var wobble_t := 0.0
var pop_t := 0.0
var crashes := 0
var unlocked: Array = []
var no_keys := false         # footage: crashes never end the ride

# Score.
var views := 0
var pot := 0.0               # views waiting in the current combo
var mult := 0
var chain: Array = []        # labels in the current combo, for the HUD
var chain_idle := 0.0
var wheelie_time := 0.0
var wheelie_start_x := 0.0
var wheelie_marks := 0
var best_wheelie := 0.0
var best_combo := 0
var tricks_done := 0
var finish_time := 0.0

var _prev_lift := false
var _pick := 0               # rotates through shout lines
var _chappal_clock := 0.0


func setup(lvl: Dictionary) -> void:
	level = lvl
	bike = BIKES[String(lvl.bike)]
	length = float(lvl.length)
	unlocked = lvl.get("tricks", [])
	var w := World.build(lvl)
	hazards = w.hazards
	buildings = w.buildings
	poles = w.poles
	crowd = w.crowd
	trees = w.trees
	v = 0.0
	if lvl.get("warden", false):
		warden = {"x": -22.0, "d": 4.5, "v": 0.0, "write_t": 0.0, "whistle_t": 0.0, "hat_t": 0.0}


func passed() -> bool:
	return result == "finished" and views >= int(level.target)


func stars() -> int:
	if not passed():
		return 0
	var target: float = level.target
	return 3 if views >= target * 2.0 else (2 if views >= target * 1.5 else 1)


func log_event(text: String) -> void:
	events.append([t, text])


# ---------------------------------------------------------------- the step

## input: gas, brake (bool), lane (-1..1, + = far side), lift (bool, wheelie),
## trick (String, on the frame it's pressed), pop (bool, on the frame).
func step(dt: float, input: Dictionary) -> void:
	t += dt
	if t < 0.0:
		return
	_step_world(dt)
	_tidy()
	if result != "":
		v = move_toward(v, 0.0, 6.0 * dt)
		x += v * dt
		return
	if crash_t > 0.0:
		_step_crash(dt)
	else:
		_step_bike(dt, input)
		_collide()
	_step_chain(dt)
	if x >= length and crash_t <= 0.0:
		_bank()
		finish_time = t
		result = "finished"
		log_event("finish %s" % ("pass" if passed() else "fail"))


func _step_bike(dt: float, input: Dictionary) -> void:
	safe_t = maxf(0.0, safe_t - dt)
	pop_t = maxf(0.0, pop_t - dt)
	wobble_t = maxf(0.0, wobble_t - dt)
	var wheelie := pitch > 8.0 and not airborne
	# Speed: the throttle pulls towards top speed, the brake slows, and with
	# neither the bike settles at cruising speed. On the back wheel the bike
	# can't go flat out.
	var top: float = bike.wheelie_top if wheelie else bike.top
	if input.get("gas", false):
		v += float(bike.accel) * dt * (1.0 - 0.6 * v / top)
	elif input.get("brake", false):
		v -= 9.0 * dt
		if v < 3.0:
			v = move_toward(v, 0.0, 9.0 * dt)
	else:
		v = move_toward(v, bike.cruise, 3.0 * dt)
	if v > top:
		v = move_toward(v, top, 5.0 * dt)
	if not input.get("brake", false):
		v = maxf(v, 3.0)
	v = maxf(v, 0.0)
	x += v * dt
	# Lanes: sideways speed eases towards what the stick asks for. Some
	# tricks take both hands off the bars, so no steering then.
	var steer := float(input.get("lane", 0.0))
	if trick != "" and not TRICKS[trick].steer:
		steer = 0.0
	var grip := 0.5 if level.get("rain", false) else 1.0
	if airborne:
		grip *= 0.5
	var want := steer * float(bike.lane)
	if skid_t > 0.0:
		skid_t -= dt
		want = skid_dir * 3.0
		grip = 0.35
	vd = move_toward(vd, want, LAT_ACCEL * grip * dt)
	d += vd * dt
	if d < 0.45 or d > World.ROAD_W - 0.45:
		d = clampf(d, 0.45, World.ROAD_W - 0.45)
		vd = 0.0
	_step_pitch(dt, input)
	# Tricks.
	var want_trick := String(input.get("trick", ""))
	if want_trick != "" and trick == "" and want_trick in unlocked and (airborne or pitch > 15.0):
		trick = want_trick
		trick_t = 0.0
		log_event("trick_start %s" % trick)
	if trick != "":
		trick_t += dt
		if trick_t >= float(TRICKS[trick].time):
			_trick_done()
	if input.get("pop", false) and pop_t <= 0.0 and level.get("pop", false):
		_pop()


## The wheelie is a balancing act. Gravity pulls the front down, harder the
## lower it is, and past the balance point (about 80 degrees) it pulls the
## bike over backwards. Holding the throttle-lift pushes it up. So: hold to
## rise, let go to fall, and feather it to sit in the green.
func _step_pitch(dt: float, input: Dictionary) -> void:
	var lift: bool = input.get("lift", false)
	if airborne:
		air_time += dt
		vh -= GRAVITY * dt
		h += vh * dt
		pitch = clampf(pitch + (70.0 if lift else -55.0) * dt, 0.0, 80.0)
		if h <= 0.0:
			_land()
		_prev_lift = lift
		return
	if lift and not _prev_lift and pitch < 5.0 and v > 4.0:
		pitch_v = 70.0      # the clutch pop that gets the front off the ground
	_prev_lift = lift
	var acc := -float(bike.grav) * sin(deg_to_rad(float(bike.balance) - pitch))
	if lift and v > 4.0:
		acc += float(bike.lift) + (40.0 if input.get("gas", false) else 0.0)
	if input.get("brake", false):
		acc -= 250.0         # the rear brake brings the front down: a real trick
	acc -= float(bike.damp) * pitch_v
	# The road is never flat: bumps nudge the angle, and the longer a
	# wheelie lasts the more the bike squirms. Long wheelies are earned.
	if pitch > 3.0:
		var squirm: float = (40.0 + WOBBLE_GROWTH * wheelie_time) * float(bike.get("squirm", 1.0))
		acc += squirm * (sin(x * 1.7) + 0.8 * sin(x * 0.63 + 1.3) + 0.5 * sin(t * 5.1))
	pitch_v += acc * dt
	pitch += pitch_v * dt
	if pitch <= 0.0:
		if pitch_v < -60.0:
			log_event("front_down")
		pitch = 0.0
		pitch_v = 0.0
		if trick != "":
			_crash("faceplant")
			return
	if pitch > LOOP_OUT:
		_crash("looped")
		return
	# Wheelie bookkeeping: an element for holding it, more for holding it long.
	if pitch > 8.0:
		if wheelie_time == 0.0:
			wheelie_start_x = x
			wheelie_marks = 0
		wheelie_time += dt
		var rate := WHEELIE_RATE * (2.0 if pitch >= SWEET.x and pitch <= SWEET.y else 1.0)
		pot += rate * dt
		if wheelie_time - dt < 0.6 and wheelie_time >= 0.6:
			_element("WHEELIE", 50)
		var dist := x - wheelie_start_x
		best_wheelie = maxf(best_wheelie, dist)
		if int(dist / 40.0) > wheelie_marks:
			wheelie_marks = int(dist / 40.0)
			_element("%dM WHEELIE" % (wheelie_marks * 40), 100)
	else:
		wheelie_time = 0.0


func _launch(kind: String) -> void:
	var power := 0.55 if kind == "ramp" else 0.32
	vh = power * v * float(bike.launch) + (1.2 if pitch > 20.0 else 0.0)
	h = 0.02
	airborne = true
	air_time = 0.0
	wheelie_time = 0.0
	pitch = maxf(pitch, 12.0 if kind == "ramp" else 6.0)
	pitch_v = 0.0
	_element("RAMP AIR" if kind == "ramp" else "BREAKER AIR", 150 if kind == "ramp" else 80)
	log_event("launch %s %.2f" % [kind, vh])


func _land() -> void:
	h = 0.0
	vh = 0.0
	airborne = false
	if trick != "":
		_crash("bailed")
		return
	if pitch > 60.0:
		_crash("backflop")
		return
	log_event("land %.2f" % air_time)
	if pitch >= 15.0:
		_element("WHEELIE LANDING", 150)
		pitch_v = 0.0
	else:
		pitch = 0.0
		pitch_v = 0.0
		if air_time > 0.7:
			_element("CLEAN LANDING", 60)
	pot += 80.0 * air_time


func _trick_done() -> void:
	var tr: Dictionary = TRICKS[trick]
	tricks_done += 1
	_element(String(tr.label), int(tr.views))
	log_event("trick %s" % trick)
	if trick == "selfie":
		for o in hazards:
			if o.kind == "baraat" and absf(float(o.x) - x) < 12.0:
				_element("SELFIE WITH DULHA", 400)
				log_event("dulha")
				break
	trick = ""


## PATAAKHA: the "tuned" silencer backfires. Pigeons scatter, crossers jump
## and hurry, goats bolt off the road, and the warden loses his hat.
func _pop() -> void:
	pop_t = POP_COOLDOWN
	v += 1.0
	log_event("pop")
	popups.append({"x": x - 0.4, "d": d, "h": 0.6, "text": "PATAAKHA!", "t0": t, "col": Color(1, 0.55, 0.1)})
	for o in hazards:
		var dx: float = float(o.x) - x
		if dx < -3.0 or dx > POP_RANGE:
			continue
		match String(o.kind):
			"pigeons":
				if o.state == "":
					_scatter(o)
			"ped":
				if o.state != "scared" and _on_road(o):
					o.state = "scared"
					o.speed = 4.0
					_element("JUMP SCARE", 60)
					_shout(float(o.x), float(o.d), 1.9, UNCLE)
			"goats":
				if o.state != "scared" and _on_road(o):
					o.state = "scared"
					o.speed = 4.5
					o.to = -1.6 if float(o.d) < World.ROAD_W / 2.0 else World.ROAD_W + 1.6
					_element("BAKRIAN BHAGAO", 60)
	if not warden.is_empty() and x - float(warden.x) < 12.0 and warden.hat_t <= 0.0:
		warden.hat_t = 1.6
		warden.write_t = maxf(float(warden.write_t), 1.0)
		_element("WARDEN'S TOPI", 100)
		log_event("hat")


func _on_road(o: Dictionary) -> bool:
	return float(o.d) > -0.3 and float(o.d) < World.ROAD_W + 0.3


func _scatter(o: Dictionary) -> void:
	o.state = "fly"
	o.fly_t = t
	_element("KABOOTAR CHAOS", 80)
	log_event("pigeons")


# ---------------------------------------------------------------- collisions

func _collide() -> void:
	if crash_t > 0.0:
		return
	var bx0 := x - 0.1
	var bx1 := x + 1.6
	for o in hazards:
		var ox: float = o.x
		if ox < x - 14.0:
			continue
		if ox > x + 14.0:
			continue
		var k: Dictionary = World.KINDS[o.kind]
		var hl: float = float(k.len) / 2.0
		var hd: float = float(k.dep) / 2.0
		var x_overlap := bx1 > ox - hl and bx0 < ox + hl
		if not x_overlap:
			continue
		var gap := absf(float(o.d) - d) - hd - 0.3
		var kind := String(o.kind)
		if gap < 0.0:
			match kind:
				"breaker", "ramp":
					if not airborne and h < 0.3:
						_launch(kind)
				"pothole":
					if not airborne and not o.hit:
						o.hit = true
						if pitch > 8.0:
							_element("POTHOLE SKIP", 40)
						else:
							v *= 0.7
							wobble_t = 0.5
							_lose_combo("pothole")
				"puddle":
					if not airborne and not o.hit:
						o.hit = true
						log_event("splash")
						if pitch > 8.0:
							_element("WHEELIE SPLASH", 80)
						else:
							skid_t = 0.55
							skid_dir = 1.0 if (int(o.look) % 2 == 0) else -1.0
							v *= 0.85
				"pigeons":
					if o.state == "":
						_scatter(o)
				_:
					if not k.solid or safe_t > 0.0 or (kind == "ped" and o.state == "done"):
						continue
					if h >= float(k.h) - 0.05:
						if not o.jumped:
							o.jumped = true
							_element("OVER THE %s" % k.label, 600 if kind == "bus" else 200)
							log_event("over %s" % kind)
					else:
						o.hit = true
						_crash(kind)
						return
		elif gap < 0.6 and k.solid and not o.near and not o.jumped and safe_t <= 0.0 \
				and _on_road(o) and (v > 6.0 or kind == "ped"):
			o.near = true
			_element("CLOSE CALL", 60)
			log_event("close %s" % kind)
			if kind == "ped":
				_shout(ox, float(o.d), 1.9, UNCLE)


func _crash(cause: String) -> void:
	crash_t = CRASH_TIME
	crash_cause = cause
	crash_v = v
	crashes += 1
	trick = ""
	airborne = false
	pot = 0.0
	mult = 0
	chain.clear()
	chain_idle = 0.0
	wheelie_time = 0.0
	views += FAIL_VIEWS
	log_event("crash %s" % cause)
	popups.append({"x": x, "d": d, "h": 2.2, "text": String(CRASH_LINES.get(cause, "OOF!")), "t0": t, "col": Color(1, 0.3, 0.25)})
	_cheer_near(LAUGH)


## The bike slides and Shani tumbles. Then he dusts off and gets back on.
func _step_crash(dt: float) -> void:
	crash_t -= dt
	v = move_toward(v, 0.0, 9.0 * dt)
	x += v * dt
	pitch = 0.0
	pitch_v = 0.0
	h = 0.0
	vh = 0.0
	vd = 0.0
	if crash_t <= 0.0:
		if crashes >= PATIENCE and not no_keys:
			result = "keys"
			finish_time = t
			log_event("keys")
			return
		crash_t = 0.0
		safe_t = SAFE_TIME
		v = float(bike.cruise)
		d = _clearest_lane()
		log_event("respawn")


func _clearest_lane() -> float:
	var best: float = World.LANES[1]
	var best_room := -1.0
	for lane in World.LANES:
		var room := 40.0
		for o in hazards:
			var k: Dictionary = World.KINDS[o.kind]
			if not k.solid:
				continue
			var dx: float = float(o.x) - x
			if dx > -4.0 and dx < room and absf(float(o.d) - lane) < float(k.dep) / 2.0 + 0.6:
				room = dx
		if room > best_room:
			best_room = room
			best = lane
	return best


# ---------------------------------------------------------------- the combo

## Stunts add views to a pot and bump the multiplier. While the front wheel
## is up (or you're in the air) the combo stays alive; a moment on two wheels
## banks it: pot x multiplier. A crash loses the lot.
func _element(label: String, value: int) -> void:
	# Repeats are worth half as much each time and don't raise the
	# multiplier: variety is what makes a combo big.
	var repeats := chain.count(label)
	pot += value * pow(0.5, repeats)
	if repeats == 0:
		mult = mini(mult + 1, MAX_MULT)
	chain.append(label)
	chain_idle = 0.0
	popups.append({"x": 0.8, "d": d, "h": 2.4 + h, "text": label, "t0": t, "col": Color(1, 0.95, 0.4), "rel": true})


func _step_chain(dt: float) -> void:
	if pot <= 0.0 or crash_t > 0.0:
		return
	if airborne or pitch > 8.0 or trick != "":
		chain_idle = 0.0
	else:
		chain_idle += dt
		if chain_idle >= CHAIN_GRACE:
			_bank()


func _bank() -> void:
	if pot <= 0.0:
		return
	var gain := int(round(pot * maxi(mult, 1)))
	views += gain
	best_combo = maxi(best_combo, gain)
	log_event("bank %d %d" % [gain, mult])
	popups.append({"x": 0.5, "d": d, "h": 3.2, "text": "+%s VIEWS" % fmt(gain), "t0": t, "col": Color(0.5, 1, 0.5), "rel": true})
	if gain >= 600:
		_cheer_near(PRAISE)
	pot = 0.0
	mult = 0
	chain.clear()
	chain_idle = 0.0


func _lose_combo(why: String) -> void:
	log_event(why)
	if pot > 0.0:
		log_event("combo_lost")
	pot = 0.0
	mult = 0
	chain.clear()


# ---------------------------------------------------------------- the world

func _step_world(dt: float) -> void:
	for o in hazards:
		var k: Dictionary = World.KINDS[o.kind]
		var kind := String(o.kind)
		if not o.active:
			var reach := ACTIVATE * (1.4 if kind == "wrongway" else 1.0)
			if float(o.x) - x < reach:
				o.active = true
				o.v = float(k.get("v", 0.0))
			else:
				continue
		match kind:
			"ped", "goats":
				_step_crosser(o, dt)
			"pigeons":
				if o.state == "fly":
					o.h_fly = float(o.get("h_fly", 0.0)) + dt * 5.0
			_:
				o.v = float(k.get("v", 0.0))   # back to its own pace, unless...
				if float(o.v) != 0.0:
					_follow(o)
					o.x = float(o.x) + float(o.v) * dt
	if not warden.is_empty():
		_step_warden(dt)
	if level.get("chappals", false):
		_step_chappals(dt)
	for c in crowd:
		c.cheer = maxf(0.0, float(c.cheer) - dt)


## Traffic doesn't drive through itself: a vehicle that catches up with a
## slower one in its lane slows to match. Shani too (they honk at him).
func _follow(o: Dictionary) -> void:
	var k: Dictionary = World.KINDS[o.kind]
	var to_bike: float = x + 0.8 - float(o.x)
	if float(o.v) > 0.0 and to_bike > 0.0 and to_bike < float(k.len) / 2.0 + 3.0 \
			and absf(d - float(o.d)) < 1.3 and v < float(o.v) and crash_t <= 0.0:
		o.v = v
		if not o.get("honked", false):
			o.honked = true
			log_event("honk")
	if float(o.v) < 0.0:
		_swerve(o)
		return
	for other in hazards:
		if is_same(other, o) or not other.active or not World.KINDS[other.kind].solid:
			continue
		var ok: Dictionary = World.KINDS[other.kind]
		if float(other.v) < 0.0:
			continue       # the ulta rickshaw gets out of everyone's way (see _swerve)
		if absf(float(other.d) - float(o.d)) > (float(k.dep) + float(ok.dep)) / 2.0 - 0.1:
			continue
		var room: float = (float(k.len) + float(ok.len)) / 2.0 + 2.5
		var dx: float = float(other.x) - float(o.x)
		if dx > 0.0 and dx < room and float(other.v) < float(o.v):
			o.v = float(other.v)


## The wrong-way rickshaw weaves: when something's coming at it in its lane
## (Shani included), it hops to the next lane over.
func _swerve(o: Dictionary) -> void:
	var od: float = o.d
	var blocked := false
	if x < float(o.x) and float(o.x) - x < 9.0 and absf(d - od) < 1.3:
		blocked = true
	for other in hazards:
		if blocked:
			break
		if is_same(other, o) or not other.active or not World.KINDS[other.kind].solid:
			continue
		var dx: float = float(o.x) - float(other.x)
		var ok: Dictionary = World.KINDS[other.kind]
		if dx > 0.0 and dx < float(ok.len) / 2.0 + 6.0 and absf(float(other.d) - od) < (1.4 + float(ok.dep)) / 2.0:
			blocked = true
	if blocked and not o.has("to_d"):
		var best: float = od
		var best_room := -1.0
		for lane in World.LANES:
			if absf(lane - od) < 1.0 or absf(lane - od) > 3.5:
				continue
			var room := 30.0
			for other in hazards:
				if is_same(other, o) or not World.KINDS[other.kind].solid:
					continue
				var dx: float = float(o.x) - float(other.x)
				if dx > -2.0 and dx < room and absf(float(other.d) - lane) < 1.5:
					room = dx
			if absf(d - lane) < 1.6 and x < float(o.x) and float(o.x) - x < 30.0:
				room = -1.0      # never swerve into Shani's lane
			if room > best_room:
				best_room = room
				best = lane
		o.to_d = best
	if o.has("to_d"):
		o.d = move_toward(od, float(o.to_d), 2.5 / 60.0)
		if is_equal_approx(float(o.d), float(o.to_d)):
			o.erase("to_d")


## Uncles and goats wait at the kerb, then cross when Shani gets close.
func _step_crosser(o: Dictionary, dt: float) -> void:
	if o.state == "" and x > float(o.x) - float(o.trigger):
		o.state = "walk"
	if o.state == "walk" or o.state == "scared":
		var to: float = o.to
		o.d = move_toward(float(o.d), to, float(o.speed) * dt)
		if is_equal_approx(float(o.d), to):
			o.state = "done"


func _step_warden(dt: float) -> void:
	var w := warden
	w.whistle_t = maxf(0.0, float(w.whistle_t) - dt)
	w.hat_t = maxf(0.0, float(w.hat_t) - dt)
	var gap: float = x - float(w.x)
	if float(w.write_t) > 0.0:
		w.write_t = float(w.write_t) - dt
		w.v = move_toward(float(w.v), 0.0, 12.0 * dt)
	else:
		# He rides a little faster than cruising, and never falls too far back.
		var want: float = float(bike.cruise) + 3.5
		if gap > 40.0:
			want = v + 3.0
		w.v = move_toward(float(w.v), want, 6.0 * dt)
	w.x = float(w.x) + float(w.v) * dt
	w.d = move_toward(float(w.d), d, 2.5 * dt)
	if result != "" or crash_t > 0.0 or safe_t > 0.0:
		return
	if gap < 14.0 and float(w.whistle_t) <= 0.0:
		w.whistle_t = 2.5
		log_event("whistle")
		bubbles.append({"x": float(w.x), "d": float(w.d), "h": 2.0, "text": "RUKO!", "t0": t})
	w.cool_t = maxf(0.0, float(w.get("cool_t", 0.0)) - dt)
	if gap < 1.6 and gap > -1.0 and absf(float(w.d) - d) < 1.3 and not airborne \
			and float(w.write_t) <= 0.0 and float(w.cool_t) <= 0.0:
		w.cool_t = 8.0     # one ticket at a time
		views = maxi(0, views - 400)
		pot = 0.0
		mult = 0
		chain.clear()
		v *= 0.5
		w.write_t = 2.5
		wobble_t = 0.5
		log_event("chalaan")
		popups.append({"x": x, "d": d, "h": 2.6, "text": "CHALAAN! -400", "t0": t, "col": Color(1, 0.3, 0.25)})
		bubbles.append({"x": float(w.x), "d": float(w.d), "h": 2.0, "text": "LICENCE DIKHAO!", "t0": t})


## Ammi runs along the rooftops ahead and throws chappals where Shani is
## about to be. Change lane or speed to make her miss.
func _step_chappals(dt: float) -> void:
	ammi_x = x + 8.0
	if t > 4.0 and x < length - 40.0 and result == "":
		_chappal_clock += dt
		if _chappal_clock >= CHAPPAL_EVERY:
			_chappal_clock = 0.0
			var ax := ammi_x
			chappals.append({
				"x0": ax, "d0": AMMI_D, "h0": AMMI_H + 1.7,
				"tx": x + v * CHAPPAL_FLIGHT + 0.8, "td": d, "t0": t, "landed": false,
				"spin": float(chappals.size() % 2) * 2.0 - 1.0,
			})
			log_event("throw")
			if chappals.size() % 3 == 1:
				bubbles.append({"x": ax, "d": AMMI_D, "h": AMMI_H + 2.2,
					"text": AMMI[int(chappals.size() / 3.0) % AMMI.size()], "t0": t})
	for c in chappals:
		if c.landed:
			continue
		var f: float = (t - float(c.t0)) / CHAPPAL_FLIGHT
		if f < 1.0:
			continue
		c.landed = true
		if crash_t > 0.0 or safe_t > 0.0:
			continue
		var dx: float = float(c.tx) - x
		var dd: float = absf(float(c.td) - d)
		if dx > -0.4 and dx < 1.9 and dd < 0.8 and h < 1.4:
			v *= 0.75
			wobble_t = 0.6
			_lose_combo("chappal")
			popups.append({"x": x, "d": d, "h": 2.6, "text": "CHAPPAL'D!", "t0": t, "col": Color(1, 0.4, 0.3)})
		elif dx > -2.0 and dx < 3.5 and dd < 2.6:
			_element("CHAPPAL DODGE", 50)


## Where a chappal is at time t: a straight line with a hop on top.
func chappal_pos(c: Dictionary) -> Vector3:
	var f: float = clampf((t - float(c.t0)) / CHAPPAL_FLIGHT, 0.0, 1.0)
	var cx: float = lerpf(float(c.x0), float(c.tx), f)
	var cd: float = lerpf(float(c.d0), float(c.td), f)
	var ch: float = lerpf(float(c.h0), 0.0, f) + 3.0 * 4.0 * f * (1.0 - f)
	return Vector3(cx, cd, ch)


func _cheer_near(lines: Array) -> void:
	var said := false
	for c in crowd:
		if absf(float(c.x) - x) < 18.0:
			c.cheer = 1.5
			if not said:
				said = true
				_shout(float(c.x), float(c.d), 1.8, lines)


func _shout(sx: float, sd: float, sh: float, lines: Array) -> void:
	_pick += 1
	bubbles.append({"x": sx, "d": sd, "h": sh, "text": String(lines[_pick % lines.size()]), "t0": t})


func _tidy() -> void:
	popups = popups.filter(func(p) -> bool: return t - float(p.t0) < 1.4)
	bubbles = bubbles.filter(func(b) -> bool: return t - float(b.t0) < 1.6)
	if chappals.size() > 12:
		chappals.pop_front()


## 12345 -> "12,345"
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
