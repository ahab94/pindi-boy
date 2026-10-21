extends RefCounted
## Two bots that ride using the same input a player gives.
##
## The expert proves every ride can be passed (checks/autoplay.sh) and rides
## every video clip. The rookie is deliberately sloppy (late lane changes, a
## shaky wheelie, forgotten tricks) so tests/sim.gd can measure how hard each
## ride feels for a person.

const World := preload("res://scripts/world.gd")
const Ride := preload("res://scripts/ride.gd")

var rookie := false
var lane_target := 4.5
var _think := 0.0
var _hold := 0.0             # the rookie's thumb: lift decisions stick for a moment
var _lift := false
var _wheelie_aim := 48.0
var _rookie_limit := 3.0
var _rng := RandomNumberGenerator.new()


func _init(seed := 7) -> void:
	_rng.seed = seed


func drive(r, dt: float) -> Dictionary:
	var input := {"gas": true, "brake": false, "lane": 0.0, "lift": false, "trick": "", "pop": false}
	if r.t < 0.0 or r.crash_t > 0.0 or r.result != "":
		_lift = false
		return input
	_think -= dt
	if _think <= 0.0:
		_think = 0.35 if rookie else 0.05
		_choose_lane(r)
		if rookie:
			_wheelie_aim = 45.0 + _rng.randf_range(-14.0, 14.0)
			if float(r.pitch) < 2.0:
				_rookie_limit = _rng.randf_range(1.5, 4.5)
	var d: float = r.d
	var vd: float = r.vd
	var err := lane_target - d
	input.lane = clampf(err * 1.4 - vd * 0.3, -1.0, 1.0) if absf(err) > 0.08 else -vd * 0.2
	# Brake when something in this lane arrives before the bike can get out
	# of the way.
	var escape: float = absf(err) / float(r.bike.lane) + (0.6 if rookie else 0.9)
	var danger := _danger_ahead(r, r.d, maxf(escape, 0.7))
	if danger:
		input.gas = false
		input.brake = true
	# Boxed in under a chappal: change speed instead so it lands short.
	for c in r.chappals:
		if not c.landed and absf(float(c.td) - lane_target) < 1.0 and absf(float(c.td) - d) < 1.2 \
				and float(r.v) > float(r.bike.cruise) * 0.6:
			input.gas = false
			input.brake = true
	input.lift = _wheelie(r, dt, danger)
	input.trick = _trick(r)
	input.pop = _pop(r)
	return input


# ---------------------------------------------------------------- lanes

## Scores each lane by what's coming in it (sooner = worse), and picks the
## cheapest. Ramps and pigeons pull the bot towards them.
func _choose_lane(r) -> void:
	var best := lane_target
	var best_cost := INF
	var current := _path_cost(r, lane_target)
	for lane in World.LANES:
		var cost := _path_cost(r, lane) + absf(lane - float(r.d)) * 0.15
		if cost < best_cost:
			best_cost = cost
			best = lane
	if best_cost < current - (4.0 if rookie else 1.0):
		lane_target = best


## A lane's own cost, plus whatever is in the lanes the bike has to cross
## on the way (only what it would meet while crossing them).
func _path_cost(r, lane: float) -> float:
	var cost := _lane_cost(r, lane)
	var speed: float = r.bike.lane
	for other in World.LANES:
		var lo := minf(float(r.d), lane)
		var hi := maxf(float(r.d), lane)
		if other > lo + 0.2 and other < hi - 0.2 or (absf(other - float(r.d)) < 1.5 and absf(other - lane) > 0.2):
			var reach_t := absf(other - float(r.d)) / speed + 0.6
			# Crawling along, the bike can hold back while it crosses, so only
			# what's right alongside matters.
			cost += _lane_cost(r, other, reach_t, float(r.v) < 4.0)
	return cost


func _lane_cost(r, lane: float, max_t := INF, crawling := false) -> float:
	var look := 1.8 if rookie else 3.2     # seconds ahead
	var cost := 0.0
	var bv: float = r.v
	for o in r.hazards:
		var dx: float = float(o.x) - float(r.x)
		if dx < -3.0 or dx > 90.0:
			continue
		var k: Dictionary = World.KINDS[o.kind]
		var kind := String(o.kind)
		var gap_x: float = dx - float(k.len) / 2.0 - 1.6
		if bv - float(o.v) < 0.3 and gap_x > 0.5 or crawling and gap_x > 1.0 and float(o.v) >= 0.0:
			continue       # it's pulling away (or keeping pace): never reached
		var rel: float = maxf(bv - float(o.v), 0.6)
		var tt: float = maxf(0.0, gap_x / rel)
		if tt > look or (o.v < 0.0 and not o.active and dx > look * bv):
			continue
		var t_out: float = tt + (float(k.len) + 1.8) / rel
		if tt > max_t:
			continue
		if k.solid:
			if kind == "ped" and o.state == "done":
				continue
			if r.airborne and _height_at(r, tt) >= float(k.h) + 0.3 and _height_at(r, t_out) >= float(k.h) + 0.3:
				continue
			var reach: float = float(k.dep) / 2.0 + 0.3 + (0.35 if rookie else 0.55)
			if _blocks(r, o, lane, tt, reach) or _blocks(r, o, lane, t_out, reach) \
					or _blocks(r, o, lane, (tt + t_out) / 2.0, reach):
				cost += 100.0 / (tt + 0.3)
		elif kind == "ramp":
			if absf(float(o.d) - lane) < float(k.dep) / 2.0:
				cost -= 18.0 / (tt + 1.0)
		elif kind == "pigeons":
			if absf(float(o.d) - lane) < 1.5 and o.state == "":
				cost -= 4.0 / (tt + 1.0)
		elif kind == "pothole" or kind == "puddle":
			if absf(float(o.d) - lane) < float(k.dep) / 2.0 + 0.4:
				cost += 6.0 / (tt + 0.5)
	for c in r.chappals:
		if c.landed:
			continue
		var tl: float = float(c.t0) + Ride.CHAPPAL_FLIGHT - float(r.t)
		if tl > max_t:
			continue
		if absf(float(c.td) - lane) < 1.3:
			cost += 60.0 / (tl + 0.3)
	return cost


## Whether hazard o will be across `lane` in `tt` seconds.
func _blocks(r, o: Dictionary, lane: float, tt: float, reach: float) -> bool:
	return absf(_d_at(r, o, tt) - lane) < reach


## Where a hazard will be across the road in `tt` seconds. Crossers start
## walking when Shani gets close, so the bot predicts that too.
func _d_at(r, o: Dictionary, tt: float) -> float:
	var kind := String(o.kind)
	if o.has("to_d"):
		return move_toward(float(o.d), float(o.to_d), 2.5 * tt)
	if kind != "ped" and kind != "goats":
		return float(o.d)
	var walk := tt
	if o.state == "":
		var start: float = maxf(0.0, (float(o.x) - float(o.trigger) - float(r.x)) / maxf(float(r.v), 1.0))
		walk = tt - start
	elif o.state == "done":
		return float(o.d)
	if walk <= 0.0:
		return float(o.d)
	return move_toward(float(o.d), float(o.to), float(o.speed) * walk)


func _height_at(r, tt: float) -> float:
	return float(r.h) + float(r.vh) * tt - 0.5 * Ride.GRAVITY * tt * tt


func _danger_ahead(r, lane: float, seconds: float) -> bool:
	for o in r.hazards:
		var k: Dictionary = World.KINDS[o.kind]
		if not k.solid:
			continue
		var dx: float = float(o.x) - float(r.x)
		if dx < -2.0 or dx > 30.0:
			continue
		var gap_x: float = dx - float(k.len) / 2.0 - 1.6
		if float(r.v) - float(o.v) < 0.3 and gap_x > 0.5:
			continue
		var rel: float = maxf(float(r.v) - float(o.v), 0.6)
		var tt: float = maxf(0.0, gap_x / rel)
		if tt < seconds and _blocks(r, o, lane, tt, float(k.dep) / 2.0 + 0.4):
			if r.airborne and _height_at(r, tt) >= float(k.h) + 0.3:
				continue
			return true
	return false


func _all_lanes_blocked(r, seconds: float) -> bool:
	for lane in World.LANES:
		if not _danger_ahead(r, lane, seconds):
			return false
	return true


# ---------------------------------------------------------------- wheelie

## Feathering: lift while the front is below the aim (looking a little ahead
## at where the angle is heading), let go above it.
func _wheelie(r, dt: float, danger: bool) -> bool:
	if r.airborne:
		# Aim for a slight wheelie landing; never land steep.
		var rem := _air_left(r)
		return float(r.pitch) < 24.0 and rem > 0.15 and not rookie
	var want := not danger and not _danger_ahead(r, lane_target, 1.6)
	if not r.warden.is_empty() and float(r.x) - float(r.warden.x) < 16.0:
		want = false     # flat out, the warden is right there
	if float(r.wheelie_time) > (_rookie_limit if rookie else 5.0):
		want = false     # the squirm keeps growing: quit while ahead
	if rookie and float(r.pitch) < 2.0 and want and _rng.randf() > 0.03:
		want = false     # a new player doesn't wheelie every chance they get
	if not rookie and float(r.pot) * maxi(int(r.mult), 1) > 2500.0 and float(r.pitch) < 8.0:
		want = false     # bank a big combo before something goes wrong
	if r.trick != "":
		want = true      # don't let the front drop mid-trick
	if not want and float(r.pitch) < 2.0:
		return false
	var aim := _wheelie_aim if want else 0.0
	var ahead: float = float(r.pitch) + float(r.pitch_v) * (0.35 if rookie else 0.22)
	if rookie:
		_hold -= dt
		if _hold > 0.0:
			return _lift
		_hold = 0.12
	_lift = want and ahead < aim
	return _lift


# ---------------------------------------------------------------- tricks

func _air_left(r) -> float:
	var vh: float = r.vh
	var g := Ride.GRAVITY
	return (vh + sqrt(maxf(0.0, vh * vh + 2.0 * g * float(r.h)))) / g


func _trick(r) -> String:
	if r.trick != "":
		return ""
	var options: Array = r.unlocked
	if options.is_empty():
		return ""
	if r.airborne:
		var rem := _air_left(r) - (_rng.randf_range(-0.15, 0.25) if rookie else 0.08)
		if rookie and _rng.randf() < 0.03:
			return ""
		var best := ""
		var best_views := 0
		for key in options:
			var tr: Dictionary = Ride.TRICKS[key]
			if float(tr.time) < rem and int(tr.views) > best_views:
				best = key
				best_views = int(tr.views)
		return best
	# On the back wheel, with nothing coming, the expert shows off too.
	var steady: bool = float(r.pitch) > 35.0 and float(r.pitch) < 58.0 and absf(float(r.pitch_v)) < 30.0
	if not steady or _danger_ahead(r, lane_target, 2.2) or absf(lane_target - float(r.d)) > 0.3:
		return ""
	for c in r.chappals:
		if not c.landed:
			return ""      # keep both hands free to dodge
	if rookie and _rng.randf() > 0.02:
		return ""
	for o in r.hazards:
		if o.kind == "baraat" and absf(float(o.x) - float(r.x)) < 9.0 and "selfie" in options:
			return "selfie"
	# Variety pays: pick the first trick not already in this combo.
	for key in options:
		if not String(Ride.TRICKS[key].label) in r.chain:
			return key if float(Ride.TRICKS[key].time) < 1.0 else ""
	return ""


func _pop(r) -> bool:
	if float(r.pop_t) > 0.0 or (rookie and _rng.randf() < 0.9):
		return false
	if not r.level.get("pop", false):
		return false
	for o in r.hazards:
		var dx: float = float(o.x) - float(r.x)
		if dx < 2.0 or dx > 13.0:
			continue
		if o.kind == "pigeons" and o.state == "":
			return true
		if o.kind == "goats" and o.state == "walk" and r._on_road(o):
			return true
	if not r.warden.is_empty() and float(r.x) - float(r.warden.x) < 9.0:
		return true
	return false
