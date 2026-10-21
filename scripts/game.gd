extends Node2D
## Pindi Boy. This script owns the current ride, feeds it input (keys, touch
## or a bot), shows the results, and keeps the menu, saves and dev flags.
## The rules live in ride.gd, the street in view.gd, the overlay in hud.gd.
##
## Dev flags go after `--`, e.g.
##   godot --path . -- --level=2 --autopilot --exit-on-end
## See CLAUDE.md for the full list.

const Levels := preload("res://scripts/levels.gd")
const Ride := preload("res://scripts/ride.gd")
const View := preload("res://scripts/view.gd")
const View3D := preload("res://scripts/view3d.gd")
const Autopilot := preload("res://scripts/autopilot.gd")
const Hud := preload("res://scripts/hud.gd")
const Sound := preload("res://scripts/sound.gd")

const SAVE_PATH := "user://progress.cfg"
const RESULT_DELAY := 2.0
const TRICK_KEYS := {"trick_1": "no_hands", "trick_2": "superman", "trick_3": "seat_stand", "trick_4": "selfie"}

enum State { MENU, PLAYING, RESULT }

var state := State.MENU
var level_index := 0
var ride
var view
var hud
var bot
var sound
var save_enabled := true
var progress := {}            # level index -> {views, stars}
var _end_timer := 0.0
var _heard := 0
var _hitstop := 0             # frames of near-freeze after a big moment
var _slowmo := 0              # frames of slow motion (only with --slowmo)
var _sim_time := 0.0
var _shot := 0
var _flags := {}
var _event_frames: Array = []
var _ride_frame0 := 0


func _ready() -> void:
	_parse_flags()
	_setup_input()
	_load_progress()
	if _flags.has("portrait"):
		get_window().size = Vector2i(720, 1280)
	_fit_screen()
	get_tree().root.size_changed.connect(_fit_screen)
	# The 3D street by default; --flat brings back the drawn 2D view.
	view = View.new() if _flags.has("flat") else View3D.new()
	add_child(view)
	sound = Sound.new()
	sound.music_on = not _flags.has("no-music")
	add_child(sound)
	if not _flags.has("no-post"):
		var post_layer := CanvasLayer.new()
		post_layer.layer = 5          # over the street, under the HUD
		add_child(post_layer)
		var post := ColorRect.new()
		post.set_anchors_preset(Control.PRESET_FULL_RECT)
		post.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://scripts/post.gdshader")
		post.material = mat
		post_layer.add_child(post)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Hud.new()
	hud.show_touch = DisplayServer.is_touchscreen_available() or _flags.has("touch")
	hud.clean = _flags.has("clean")
	view.zoom = float(_flags.get("zoom", 1.0))
	hud.progress = progress
	layer.add_child(hud)
	hud.retry_pressed.connect(func() -> void: start_level(level_index))
	hud.next_pressed.connect(_next_level)
	hud.menu_pressed.connect(show_menu)
	hud.level_chosen.connect(start_level)
	if _flags.has("touch"):
		Input.emulate_touch_from_mouse = true
	if _flags.has("level"):
		start_level(int(_flags.level))
	else:
		show_menu()


## Phones held upright get a portrait base size so text stays readable.
## Godot note: with stretch mode "canvas_items" + aspect "expand", the
## content scale size is the smallest area the game promises to show; the
## window's shape decides what extra you see.
func _fit_screen() -> void:
	var win := get_window()
	var s := win.size
	win.content_scale_size = Vector2i(720, 1280) if s.y > s.x else Vector2i(1280, 720)


func start_level(i: int) -> void:
	level_index = clampi(i, 0, Levels.count() - 1)
	ride = Ride.new()
	ride.setup(_level_data(level_index))
	ride.no_keys = _flags.has("no-keys")
	if _flags.has("start"):
		# Footage: begin further down the road.
		ride.x = float(_flags.start)
		if not ride.warden.is_empty():
			ride.warden.x = ride.x - 22.0
	_attach(ride)
	hud.racing = true
	hud.hide_panels()
	bot = null
	if _flags.has("autopilot") or _flags.has("rookie"):
		bot = Autopilot.new()
		bot.rookie = _flags.has("rookie")
		for key in ["fail", "fail_after", "loop_at", "long", "no_dodge", "dawdle", "aim"]:
			var flag: String = String(key).replace("_", "-")
			if _flags.has(flag):
				bot.director[key] = _flags[flag]
	state = State.PLAYING
	_end_timer = RESULT_DELAY
	_event_frames.clear()
	_ride_frame0 = Engine.get_frames_drawn()
	sound.play_music("ride")


## The level, with footage set pieces added by --place=x:kind:lane,...
## (--only-placed drops the random scatter, for a clean stunt run).
func _level_data(i: int) -> Dictionary:
	var lvl: Dictionary = Levels.get_level(i).duplicate(true)
	if _flags.has("only-placed"):
		lvl.scatter = {}
	if _flags.has("place"):
		var placed: Array = lvl.get("placed", []).duplicate()
		for item in String(_flags.place).split(","):
			var parts := item.split(":")
			placed.append([float(parts[0]), parts[1], int(parts[2]) if parts.size() > 2 else 1, parts.size() > 3 and parts[3] == "p"])
		lvl.placed = placed
	if _flags.has("tricks"):
		lvl.tricks = Array(String(_flags.tricks).split("+"))
	return lvl


func _attach(r) -> void:
	view.ride = r
	view.reset()
	hud.new_ride(r)
	_heard = 0


## The menu sits over a demo ride that the autopilot plays, like an arcade
## attract mode.
func show_menu() -> void:
	state = State.MENU
	ride = Ride.new()
	ride.setup(Levels.get_level(4))
	ride.t = 0.0
	_attach(ride)
	hud.racing = false
	bot = Autopilot.new()
	sound.play_music("menu")
	hud.progress = progress
	hud.show_menu()


func _next_level() -> void:
	if level_index + 1 < Levels.count():
		start_level(level_index + 1)
	else:
		show_menu()


# ---------------------------------------------------------------- the ride

func _physics_process(delta: float) -> void:
	_sim_time += delta
	if _flags.has("timeout") and _sim_time > float(_flags.timeout):
		_report("timeout")
	if ride == null:
		return
	var input: Dictionary = bot.drive(ride, delta) if bot else _read_input()
	var before: float = ride.t
	ride.step(delta, input)
	if state == State.PLAYING:
		_sounds(before)
		sound.engine(String(ride.level.bike), float(ride.v), float(ride.bike.top), ride.pitch > 8.0,
			ride.t > -2.5 and ride.crash_t <= 0.0 and ride.result == "")
	elif state == State.MENU:
		sound.engine("70", 0.0, 1.0, false, false)
		if ride.result != "" or ride.x > ride.length - 5.0:
			show_menu()
			return
	if state == State.PLAYING and ride.result != "":
		_end_timer -= delta
		if _end_timer <= 0.0:
			_finish()
	if _flags.has("trace") and fmod(_sim_time, 0.5) < delta:
		print("TRACE t=%.1f x=%.0f d=%.2f v=%.1f pitch=%.0f h=%.2f views=%d pot=%.0f x%d crashes=%d" % [
			ride.t, ride.x, ride.d, ride.v, ride.pitch, ride.h, ride.views, ride.pot, ride.mult, ride.crashes])


func _sounds(before: float) -> void:
	for i in range(_heard, ride.events.size()):
		var ev := String(ride.events[i][1])
		sound.play_event(ev)
		_juice(ev)
		# Video time of the event: frames drawn since the ride began. Slow
		# motion stretches ride time, so videos are cut by this instead.
		_event_frames.append(Engine.get_frames_drawn() - _ride_frame0)
	_heard = ride.events.size()
	for mark in [-3.0, -2.0, -1.0]:
		if before < mark + 0.001 and ride.t >= mark + 0.001 and mark > -3.0:
			sound.play("tick")
	if before < 0.0 and ride.t >= 0.0:
		sound.play("go")


## A split-second freeze on crashes and big landings sells the hit. Slow
## motion is only for recordings (--slowmo): in play it feels like a penalty.
func _juice(ev: String) -> void:
	if _flags.has("no-slowmo"):
		return
	var key := ev.split(" ")[0]
	match key:
		"crash", "chappal", "chalaan":
			_hitstop = maxi(_hitstop, 4)
			if _flags.has("slowmo"):
				_slowmo = maxi(_slowmo, 60)
		"launch":
			if _flags.has("slowmo") and ev.contains("ramp"):
				_slowmo = maxi(_slowmo, 50)
		"over":
			if _flags.has("slowmo"):
				_slowmo = maxi(_slowmo, 40)


func _read_input() -> Dictionary:
	var trick := ""
	for action in TRICK_KEYS:
		if Input.is_action_just_pressed(action):
			trick = TRICK_KEYS[action]
	return {
		"gas": Input.is_action_pressed("gas"),
		"brake": Input.is_action_pressed("brake"),
		"lane": Input.get_axis("down", "up"),
		"lift": Input.is_action_pressed("wheelie"),
		"trick": trick,
		"pop": Input.is_action_just_pressed("pop"),
	}


func _finish() -> void:
	state = State.RESULT
	hud.racing = false
	sound.engine("70", 0.0, 1.0, false, false)
	var lvl: Dictionary = ride.level
	var stars: int = ride.stars()
	var title := ""
	var lines: Array = []
	if ride.result == "keys":
		title = "ABBU TOOK THE KEYS"
		lines.append("Three crashes. The 70 is grounded until further notice.")
	elif stars > 0:
		title = ["VIRAL!", "MEGA VIRAL!", "PINDI FAMOUS!"][stars - 1]
		lines.append(String(lvl.win))
	else:
		title = "%s VIEWS (3 ARE AMMI)" % Ride.fmt(ride.views)
		lines.append("Needed %s. More wheelies, more tricks, longer combos." % Ride.fmt(int(lvl.target)))
	lines.append("Views %s / %s" % [Ride.fmt(ride.views), Ride.fmt(int(lvl.target))])
	lines.append("Best combo %s   Longest wheelie %dm   Tricks %d   Crashes %d" % [
		Ride.fmt(ride.best_combo), int(ride.best_wheelie), ride.tricks_done, ride.crashes])
	var old: Dictionary = progress.get(level_index, {"views": 0, "stars": 0})
	if bot == null and (ride.views > int(old.views) or stars > int(old.stars)):
		progress[level_index] = {"views": maxi(ride.views, int(old.views)), "stars": maxi(stars, int(old.stars))}
		if ride.views > int(old.views) and int(old.views) > 0:
			lines.append("NEW BEST!")
	_save_progress()
	sound.play_music("")
	hud.show_result(title, lines, stars, stars > 0 and level_index + 1 < Levels.count())
	_report(String(ride.result))


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("retry") and state != State.MENU:
		start_level(level_index)
	elif event.is_action_pressed("menu"):
		if state != State.MENU:
			show_menu()
	elif event.is_action_pressed("next") and state == State.RESULT:
		if ride.passed():
			_next_level()
		else:
			start_level(level_index)


func _process(_delta: float) -> void:
	# Engine.time_scale slows the whole game, physics included.
	var scale := 1.0
	if _hitstop > 0:
		_hitstop -= 1
		scale = 0.08
	elif _slowmo > 0:
		_slowmo -= 1
		scale = 0.35
	if state != State.PLAYING:
		scale = 1.0
	Engine.time_scale = scale
	if not _flags.has("screenshot"):
		return
	# --wait=S takes one shot; --wait=1,2.5,4 takes a numbered shot at each.
	var waits: PackedStringArray = String(_flags.get("wait", "1.5")).split(",")
	if _shot < waits.size() and _sim_time >= float(waits[_shot]):
		var path := String(_flags.screenshot)
		if waits.size() > 1:
			path = path.get_basename() + "_%d.png" % _shot
		get_viewport().get_texture().get_image().save_png(path)
		print("SCREENSHOT ", path)
		_shot += 1
		if _shot >= waits.size():
			get_tree().quit()


func _setup_input() -> void:
	_add_action("gas", [KEY_RIGHT, KEY_D])
	_add_action("brake", [KEY_LEFT, KEY_A])
	_add_action("up", [KEY_UP, KEY_W])
	_add_action("down", [KEY_DOWN, KEY_S])
	_add_action("wheelie", [KEY_SPACE, KEY_SHIFT])
	_add_action("trick_1", [KEY_J])
	_add_action("trick_2", [KEY_K])
	_add_action("trick_3", [KEY_L])
	_add_action("trick_4", [KEY_U])
	_add_action("pop", [KEY_X])
	_add_action("retry", [KEY_R])
	_add_action("next", [KEY_ENTER, KEY_KP_ENTER])
	_add_action("menu", [KEY_ESCAPE])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


# ---------------------------------------------------------------- saves, flags, reports

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if not save_enabled or _flags.has("fresh") or cfg.load(SAVE_PATH) != OK:
		return
	for i in Levels.count():
		if cfg.has_section_key("views", str(i)):
			progress[i] = {"views": int(cfg.get_value("views", str(i))), "stars": int(cfg.get_value("stars", str(i), 0))}


func _save_progress() -> void:
	if not save_enabled or bot != null:
		return
	var cfg := ConfigFile.new()
	for i in progress:
		cfg.set_value("views", str(i), progress[i].views)
		cfg.set_value("stars", str(i), progress[i].stars)
	cfg.save(SAVE_PATH)


func _parse_flags() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg).trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			_flags[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			_flags[a] = true


## With --exit-on-end, prints one machine-readable line and quits. The checks
## and the video tools parse it; --log-events adds every event with its time.
func _report(outcome: String) -> void:
	if not _flags.has("exit-on-end"):
		return
	if _flags.has("log-events") and ride:
		for i in ride.events.size():
			var e: Array = ride.events[i]
			var vid: float = float(_event_frames[i]) / 60.0 if i < _event_frames.size() else -1.0
			print("EVENT t=%.2f v=%.3f %s" % [e[0], vid, e[1]])
	print("RESULT level=%d %s views=%d target=%d stars=%d crashes=%d time=%.1f" % [level_index, outcome,
		ride.views if ride else 0, int(ride.level.target) if ride else 0, ride.stars() if ride else 0,
		ride.crashes if ride else 0, ride.t if ride else 0.0])
	get_tree().quit()
