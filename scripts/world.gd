extends RefCounted
## The street for one ride: hazards on the road, plus the buildings, poles
## and spectators along it. Everything comes from the level's seed, so a
## ride is the same street every time (the bots and the videos rely on it).
##
## World axes (metres):
##   x  along the road, the way Shani rides (screen right)
##   d  across the road: 0 is the near kerb, ROAD_W the far kerb (screen up-right)
##   h  height above the road (screen up)

const ROAD_W := 9.0
const LANES := [1.5, 4.5, 7.5]
const NEAR_WALK := -2.4       # near footpath edge
const FAR_WALK := 11.6        # far footpath edge, where shop fronts start
const START_CLEAR := 60.0     # nothing in the first stretch: learn the controls
const END_CLEAR := 30.0

## len: size along the road, dep: across it, h: height.
## v: speed along the road once it starts moving (+ = same way as Shani).
## solid: you crash into it unless you're above it.
## live: it moves by its own rules in ride.gd (crossers, flocks).
## gap: the clear space world.gd keeps around it when placing.
const KINDS := {
	"cart": {"len": 2.3, "dep": 1.3, "h": 1.15, "v": 0.6, "solid": true, "label": "THELA", "gap": 10.0},
	"eggs": {"len": 2.3, "dep": 1.3, "h": 1.15, "v": 0.5, "solid": true, "label": "ANDAY WALA", "gap": 10.0},
	"rickshaw": {"len": 2.7, "dep": 1.4, "h": 1.8, "v": 5.5, "solid": true, "label": "RICKSHAW", "gap": 18.0},
	"wrongway": {"len": 2.7, "dep": 1.4, "h": 1.8, "v": -5.0, "solid": true, "label": "ULTA RICKSHAW", "gap": 24.0},
	"wagon": {"len": 4.4, "dep": 1.8, "h": 2.0, "v": 7.0, "solid": true, "label": "WAGON", "gap": 22.0},
	"bus": {"len": 10.5, "dep": 2.4, "h": 3.3, "v": 4.5, "solid": true, "label": "BUS", "gap": 30.0},
	"baraat": {"len": 9.0, "dep": 5.0, "h": 2.6, "v": 1.4, "solid": true, "label": "BARAAT", "gap": 40.0},
	"ped": {"len": 0.6, "dep": 0.6, "h": 1.7, "v": 0.0, "solid": true, "label": "UNCLE", "gap": 14.0, "live": true},
	"goats": {"len": 2.6, "dep": 1.3, "h": 0.9, "v": 0.0, "solid": true, "label": "BAKRIAN", "gap": 16.0, "live": true},
	"pothole": {"len": 1.1, "dep": 1.3, "h": 0.0, "solid": false, "gap": 7.0},
	"puddle": {"len": 3.4, "dep": 2.2, "h": 0.0, "solid": false, "gap": 10.0},
	"pigeons": {"len": 2.6, "dep": 2.2, "h": 0.0, "solid": false, "gap": 12.0, "live": true},
	"breaker": {"len": 0.8, "dep": ROAD_W, "h": 0.16, "solid": false, "gap": 26.0, "wide": true},
	"ramp": {"len": 2.8, "dep": 1.7, "h": 0.95, "solid": false, "gap": 26.0},
}
## The road-blocking kinds. world.gd never lets these close all three lanes.
const SOLID_STATIC := ["cart", "eggs", "goats", "ped"]

const WALL_COLORS := [
	Color(0.93, 0.82, 0.62), Color(0.72, 0.86, 0.72), Color(0.95, 0.70, 0.72),
	Color(0.68, 0.82, 0.92), Color(0.96, 0.90, 0.70), Color(0.85, 0.78, 0.92),
	Color(0.90, 0.88, 0.84), Color(0.98, 0.78, 0.55),
]
## Shop signs, the way Pindi spells them.
const SIGNS := [
	"TIKKA HOUSE", "MOBILE REPAIR", "HAIR SALOON", "TAILOR MASTER", "CHAI KHANA",
	"PHOTOSTATE", "DRY CLEANERS", "ELECTRIC STORE", "GENERAL STORE", "SAMOSA CORNER",
	"BIKE WORKSHOP", "SWEETS & BAKERS", "CELL POINT", "KARYANA STORE", "LASSI POINT",
	"DENTAL CLINIC", "COMPUTER ACADEMY", "SHOE PALACE", "JUICE CORNER", "BIRYANI CENTRE",
	"SILENCER SPECIALIST", "SPARE PARTS", "FRUIT CHAAT", "TUITION CENTRE",
]
const SIGN_COLORS := [
	Color(0.85, 0.12, 0.15), Color(0.10, 0.45, 0.80), Color(0.10, 0.55, 0.25),
	Color(0.95, 0.65, 0.05), Color(0.45, 0.15, 0.55), Color(0.08, 0.08, 0.1),
]
const CLOTHES := [
	Color(0.95, 0.95, 0.92), Color(0.55, 0.75, 0.9), Color(0.75, 0.6, 0.45),
	Color(0.45, 0.5, 0.45), Color(0.9, 0.55, 0.6), Color(0.35, 0.4, 0.6),
	Color(0.85, 0.8, 0.55), Color(0.6, 0.3, 0.3),
]


## Builds the street. Returns {hazards, buildings, poles, crowd}.
static func build(level: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(level.seed)
	var length: float = level.length
	var hazards: Array = []
	for p in level.get("placed", []):
		hazards.append(make(String(p[1]), float(p[0]), int(p[2]), rng))
	var kinds: Array = level.get("scatter", {}).keys()
	kinds.sort()   # dictionary order isn't something to rely on for a seed
	# Place the big, picky things first so they get the room they need.
	kinds.sort_custom(func(a, b) -> bool: return float(KINDS[a].gap) > float(KINDS[b].gap))
	for kind in kinds:
		for i in int(level.scatter[kind]):
			for attempt in 60:
				var x := rng.randf_range(START_CLEAR, length - END_CLEAR)
				var lane := rng.randi_range(0, 2)
				if _fits(hazards, kind, x, lane):
					hazards.append(make(kind, x, lane, rng))
					break
	hazards.sort_custom(func(a, b) -> bool: return a.x < b.x)
	return {
		"hazards": hazards,
		"buildings": _buildings(rng, length),
		"poles": _poles(rng, length),
		"crowd": _crowd(rng, length),
		"trees": _trees(rng, length),
	}


## One hazard as a plain dictionary. ride.gd adds its live state.
static func make(kind: String, x: float, lane: int, rng: RandomNumberGenerator) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var d: float = LANES[clampi(lane, 0, 2)]
	if k.get("wide", false):
		d = ROAD_W / 2.0
	elif kind == "baraat":
		d = 3.0 if lane < 2 else 6.0     # two lanes wide
	var h := {
		"kind": kind, "x": x, "d": d, "x0": x, "d0": d, "lane": lane,
		"active": false, "v": 0.0, "vd": 0.0, "look": rng.randi() % 1000,
		"near": false, "jumped": false, "hit": false, "state": "",
	}
	if kind == "ped" or kind == "goats":
		# Crossers wait on a footpath and walk over when Shani gets close.
		var from_far := rng.randf() < 0.5
		h.d = ROAD_W + 1.2 if from_far else -1.2
		h.d0 = h.d
		h.to = -1.4 if from_far else ROAD_W + 1.4
		h.speed = 1.5 if kind == "ped" else 1.0
		h.trigger = 20.0 + float(rng.randi() % 8)
	return h


## Keeps the road passable: no two things of the same lane too close, and
## never all three lanes blocked by slow solids at the same spot.
static func _fits(hazards: Array, kind: String, x: float, lane: int) -> bool:
	var k: Dictionary = KINDS[kind]
	var wide: bool = k.get("wide", false) or kind == "ped" or kind == "goats"
	var lanes_here := {}
	for o in hazards:
		var ok: Dictionary = KINDS[o.kind]
		var gap: float = maxf(float(k.gap), float(ok.gap)) * (1.0 if kind == "baraat" or o.kind == "baraat" else 0.5)
		var dx: float = absf(float(o.x) - x)
		var other_wide: bool = ok.get("wide", false) or o.kind == "ped" or o.kind == "goats"
		var same_lane: bool = wide or other_wide or int(o.lane) == lane \
				or (o.kind == "baraat" and absf(LANES[lane] - float(o.d)) < 3.0) \
				or (kind == "baraat" and absf(LANES[int(o.lane)] - (3.0 if lane < 2 else 6.0)) < 3.0)
		if same_lane and dx < gap:
			return false
		# Ramps and breakers need a clear run-up and landing in every lane.
		if (kind in ["ramp", "breaker"] or o.kind in ["ramp", "breaker"]) and dx < 9.0:
			return false
		if o.kind in SOLID_STATIC and dx < 8.0:
			lanes_here[int(o.lane)] = true
	if kind in SOLID_STATIC:
		lanes_here[lane] = true
		if lanes_here.size() >= 3:
			return false
	return true


static func _buildings(rng: RandomNumberGenerator, length: float) -> Array:
	var out: Array = []
	var x := -80.0
	while x < length + 140.0:
		var w := rng.randf_range(5.0, 11.0)
		var floors := rng.randi_range(1, 4)
		var b := {
			"x0": x, "x1": x + w, "h": 1.0 + floors * 3.0 + rng.randf_range(0.0, 0.8),
			"floors": floors, "color": WALL_COLORS[rng.randi() % WALL_COLORS.size()],
			"sign": SIGNS[rng.randi() % SIGNS.size()],
			"sign_color": SIGN_COLORS[rng.randi() % SIGN_COLORS.size()],
			"shutter": rng.randf() < 0.3, "tank": rng.randf() < 0.55, "dish": rng.randf() < 0.35,
			"ac": rng.randf() < 0.5, "balcony": floors > 1 and rng.randf() < 0.5,
			"setback": rng.randf_range(0.0, 0.6), "seed": rng.randi(),
		}
		out.append(b)
		x += w + (0.0 if rng.randf() < 0.75 else rng.randf_range(0.5, 2.0))
	return out


static func _poles(rng: RandomNumberGenerator, length: float) -> Array:
	var out: Array = []
	var x := -60.0
	while x < length + 120.0:
		out.append({"x": x, "h": rng.randf_range(7.5, 9.0), "lean": rng.randf_range(-0.06, 0.06)})
		x += rng.randf_range(24.0, 34.0)
	return out


## Neem trees along the far footpath.
static func _trees(rng: RandomNumberGenerator, length: float) -> Array:
	var out: Array = []
	var x := -40.0 + rng.randf_range(0.0, 20.0)
	while x < length + 100.0:
		out.append({"x": x, "h": rng.randf_range(4.8, 6.5), "r": rng.randf_range(1.7, 2.4), "seed": rng.randi()})
		x += rng.randf_range(30.0, 70.0)
	return out


## Spectators on the far footpath. They cheer, gasp and shout.
static func _crowd(rng: RandomNumberGenerator, length: float) -> Array:
	var out: Array = []
	var x := 8.0
	while x < length + 60.0:
		out.append({
			"x": x, "d": rng.randf_range(9.9, 11.2), "look": rng.randi() % 1000,
			"cloth": CLOTHES[rng.randi() % CLOTHES.size()], "kid": rng.randf() < 0.25,
			"aunty": rng.randf() < 0.3, "cheer": 0.0,
		})
		x += rng.randf_range(7.0, 22.0)
	return out


## The roof height at x (Ammi throws chappals from up there).
static func roof_at(buildings: Array, x: float) -> float:
	for b in buildings:
		if x >= float(b.x0) and x < float(b.x1):
			return float(b.h)
	return 4.0
