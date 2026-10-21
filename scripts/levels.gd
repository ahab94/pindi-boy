extends RefCounted
## The ten rides, as data. Each one introduces one new thing.
##
## Fields:
##   name, blurb     menu and intro card
##   tip             one line shown at the start (how to use the new thing)
##   bike            "70" or "125" (see ride.gd BIKES)
##   length          metres from the start to Shani's front door
##   target          views needed to pass. 1.5x = two stars, 2x = three.
##                   Tuned so the rookie bot's views / target falls ride by
##                   ride from about 1.6 to 0.8 (tests/sim.gd --rookie).
##   tricks          trick keys unlocked on this ride (ride.gd TRICKS)
##   scatter         kind -> how many world.gd places at random (seeded)
##   placed          [x, kind, lane] for set pieces (lane 0 near .. 2 far, -1 = any)
##   pop             the PATAAKHA silencer (X) works
##   warden, chappals, rain    the special rules
##   sky             palette name (view.gd SKIES)
##   seed            same seed = same street every time
##   win             the line on the results card when you pass

const ALL_TRICKS := ["no_hands", "superman", "seat_stand", "selfie"]

const LEVELS := [
	{
		"name": "Gali Number 4",
		"blurb": "First day with Abbu's 70. The whole gali is watching.",
		"tip": "Hold SPACE to wheelie, let go to drop it. Keep the needle in the green. Wheelie over potholes!",
		"bike": "70", "length": 470, "target": 4000, "tricks": [],
		"scatter": {"cart": 3, "pothole": 7, "pigeons": 2},
		"sky": "morning", "seed": 104,
		"win": "Gali-famous. Even the doodhwala subscribed.",
	},
	{
		"name": "Speed Breaker Wali Sarak",
		"blurb": "Seven speed breakers in one road. Somebody really hated speed.",
		"tip": "Speed breakers launch you. In the air press J for NO HANDS. Land with both wheels!",
		"bike": "70", "length": 520, "target": 13500, "tricks": ["no_hands"],
		"scatter": {"breaker": 7, "pothole": 4, "cart": 2},
		"sky": "morning", "seed": 207,
		"win": "Airtime! The breakers finally did something useful.",
	},
	{
		"name": "Raja Bazaar Rush",
		"blurb": "Rickshaws, thelas and uncles who cross without looking.",
		"tip": "Squeeze past traffic for CLOSE CALLS. Keep a combo going and the views multiply.",
		"bike": "70", "length": 600, "target": 11500, "tricks": ["no_hands"],
		"scatter": {"rickshaw": 6, "wagon": 2, "cart": 4, "ped": 6, "pothole": 3, "breaker": 3},
		"sky": "noon", "seed": 311,
		"win": "Bazaar conquered. Three uncles want your number (to complain).",
	},
	{
		"name": "Pataakha Silencer",
		"blurb": "Shani got the silencer 'tuned'. The whole mohalla knows.",
		"tip": "Press X: PATAAKHA! It scatters pigeons, scares uncles and moves goats out of the road.",
		"pop": true, "bike": "70", "length": 620, "target": 20000, "tricks": ["no_hands"],
		"scatter": {"pigeons": 6, "goats": 3, "ped": 5, "rickshaw": 4, "breaker": 3, "cart": 2, "pothole": 3},
		"sky": "noon", "seed": 419,
		"win": "Every pigeon in Pindi now has trust issues.",
	},
	{
		"name": "The Plank Ramp",
		"blurb": "Someone leaned a plank on a pile of bricks. It's basically an invitation.",
		"tip": "Ramps send you flying over thelas. Press K in the air for SUPERMAN.",
		"pop": true, "bike": "70", "length": 680, "target": 30000, "tricks": ["no_hands", "superman"],
		"scatter": {"ramp": 5, "cart": 4, "eggs": 2, "rickshaw": 4, "wagon": 2, "breaker": 2, "pigeons": 2},
		"sky": "golden", "seed": 523,
		"win": "Over the anday wala! The eggs survived. Mostly.",
	},
	{
		"name": "Warden Sahab",
		"blurb": "A traffic warden has seen the channel. He has a whistle and a ticket book.",
		"tip": "The warden chases you. Wheelies are slow, so don't let him catch you: CHALAAN costs views.",
		"pop": true, "bike": "70", "length": 720, "target": 32500, "tricks": ["no_hands", "superman"], "warden": true,
		"scatter": {"rickshaw": 6, "wagon": 3, "bus": 1, "ramp": 3, "breaker": 3, "ped": 4, "pothole": 4, "pigeons": 2},
		"sky": "golden", "seed": 631,
		"win": "Outran the law (it was on foot for a bit, to be fair).",
	},
	{
		"name": "Sawa-Sau Day",
		"blurb": "Chachu lent Shani his 125 for ONE day. What could go wrong.",
		"tip": "The 125 is faster and flies further. L in the air for SEAT STAND. Watch for ulta rickshaws!",
		"pop": true, "bike": "125", "length": 820, "target": 49000, "tricks": ["no_hands", "superman", "seat_stand"],
		"scatter": {"wrongway": 4, "bus": 2, "wagon": 3, "rickshaw": 4, "ramp": 4, "breaker": 3, "eggs": 2, "pigeons": 3},
		"sky": "noon", "seed": 743,
		"win": "Returned the 125 with only one new scratch. Chachu didn't notice. Yet.",
	},
	{
		"name": "Barish in Pindi",
		"blurb": "It rained for ten minutes. The roads are now lakes.",
		"tip": "Puddles skid you sideways and kill your speed. Wheelie through them to keep control.",
		"pop": true, "bike": "125", "length": 820, "target": 44000, "tricks": ["no_hands", "superman", "seat_stand"], "rain": true,
		"scatter": {"puddle": 9, "pothole": 6, "rickshaw": 5, "wagon": 3, "bus": 1, "ramp": 3, "breaker": 3, "ped": 3, "wrongway": 2},
		"sky": "rain", "seed": 853,
		"win": "Soaked, muddy, viral.",
	},
	{
		"name": "Shaadi Season",
		"blurb": "Three baraats on one road. The dhol never stops.",
		"tip": "U is SELFIE. Snap one next to the dulha's horse for a huge bonus.",
		"pop": true, "bike": "125", "length": 860, "target": 59500, "tricks": ["no_hands", "superman", "seat_stand", "selfie"],
		"scatter": {"baraat": 3, "rickshaw": 4, "wagon": 3, "ramp": 4, "breaker": 3, "pigeons": 3, "eggs": 2, "wrongway": 2},
		"sky": "dusk", "seed": 967,
		"win": "Shani is now in four wedding videos. Two families want him to dance at the mehndi.",
	},
	{
		"name": "Ammi Ki Dawai",
		"blurb": "Ammi sent Shani for her medicine. Ammi has also seen the videos.",
		"tip": "Ammi is on the rooftops with chappals. Dodge them. The warden is back too. Get home!",
		"pop": true, "bike": "125", "length": 900, "target": 46000, "tricks": ["no_hands", "superman", "seat_stand", "selfie"],
		"warden": true, "chappals": true,
		"scatter": {"rickshaw": 5, "wagon": 3, "bus": 2, "wrongway": 3, "ramp": 4, "breaker": 3, "ped": 4, "pigeons": 3, "goats": 2, "eggs": 1, "pothole": 4},
		"sky": "evening", "seed": 1071,
		"win": "Medicine delivered. Ammi is proud. Ammi has also taken the keys.",
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]
