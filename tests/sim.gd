extends SceneTree
## Rides every level with a bot, with no window, and prints how it went.
##   godot --headless --path . --script res://tests/sim.gd              (expert)
##   godot --headless --path . --script res://tests/sim.gd -- --rookie  (5 rookies per ride, averaged)
## For the rookie the "ratio" (views / target) should fall ride by ride,
## from about 1.6 to 0.8: that's the difficulty curve. The expert must stay
## comfortably above 1 everywhere.

const Levels := preload("res://scripts/levels.gd")
const Ride := preload("res://scripts/ride.gd")
const Autopilot := preload("res://scripts/autopilot.gd")


func _initialize() -> void:
	var rookie := "--rookie" in OS.get_cmdline_user_args()
	var only := -1
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--level="):
			only = int(String(a).split("=")[1])
	var runs := 8 if rookie else 1
	for i in Levels.count():
		if only >= 0 and i != only:
			continue
		var lvl: Dictionary = Levels.get_level(i)
		var total := 0.0
		var crashes := 0
		var passes := 0
		var keys := 0
		var causes := {}
		var t := 0.0
		for run in runs:
			var r = Ride.new()
			r.setup(lvl)
			var bot = Autopilot.new(11 + run * 7)
			bot.rookie = rookie
			var steps := 0
			var verbose := "--verbose" in OS.get_cmdline_user_args()
			var seen := 0
			while r.result == "" and steps < 60 * 300:
				var inp: Dictionary = bot.drive(r, 1.0 / 60.0)
				r.step(1.0 / 60.0, inp)
				steps += 1
				if verbose:
					for e in range(seen, r.events.size()):
						var ev := String(r.events[e][1])
						if ev.begins_with("crash") or ev == "chalaan" or ev == "chappal":
							print("  t=%.2f %s x=%.1f d=%.2f v=%.1f pitch=%.0f h=%.2f lane_target=%.1f trick=%s" % [r.t, ev, r.x, r.d, r.v, r.pitch, r.h, bot.lane_target, r.trick])
							for o in r.hazards:
								if absf(float(o.x) - r.x) < 8.0:
									print("     %s x=%.1f d=%.2f v=%.1f state=%s" % [o.kind, o.x, o.d, o.v, o.state])
					seen = r.events.size()
			total += r.views
			crashes += r.crashes
			passes += 1 if r.passed() else 0
			keys += 1 if r.result == "keys" else 0
			t += r.t
			for e in r.events:
				var ev := String(e[1])
				if ev.begins_with("crash") or ev in ["chalaan", "chappal", "pothole"]:
					causes[ev] = int(causes.get(ev, 0)) + 1
		var avg := total / runs
		print("L%d %-26s views=%6d target=%6d ratio=%.2f crashes=%.1f pass=%d/%d keys=%d time=%.0fs  %s" % [
			i + 1, lvl.name, avg, lvl.target, avg / float(lvl.target), float(crashes) / runs,
			passes, runs, keys, t / runs, causes])
	quit(0)
