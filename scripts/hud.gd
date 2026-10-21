extends Control
## Everything on top of the street: the views counter, the combo, Abbu's
## patience, the wheelie gauge, the live chat, the countdown, the results
## card, the menu and the touch buttons.
##
## Godot note: this Control fills the screen and mostly draws itself in
## _draw(). The menu and results use real Button nodes, so clicks, taps and
## keyboard focus come for free.

signal retry_pressed
signal next_pressed
signal menu_pressed
signal level_chosen(index: int)

const Ride := preload("res://scripts/ride.gd")
const Levels := preload("res://scripts/levels.gd")

const HANDLES := ["pindi_munda_07", "chai_wala_99", "saddar_ka_sher", "rani.pk", "kamran_bhai",
	"tuition_sir", "gamer_jani", "nosy_aunty", "bobby_fresh", "waqas.official", "silencer_king",
	"doodh_wala", "abbu_ka_phone", "raja_bazaar_reporter", "pigeon_rights_pk", "warden_ki_beti"]
const CHAT := {
	"bank": ["oye jakat!!", "ustaad ji kamaal", "sahi gal ae pai", "jakat banda ae", "bhai kamaal", "LEGEND", "pindi boys >>>", "W", "scene on hai!!", "sub kar diya", "ye banda alag hai", "again again"],
	"crash": ["raja bazar jaso, wahan helmet milta", "ustaad gir gaya lol", "oye khotay", "LOL", "F", "helmet kahan hai pai", "ammi ko bata diya", "HAHAHAHA", "bike ka kya kasoor tha", "replay pls", "clip it"],
	"pop": ["committee chowk tak awaaz gayi", "jakat silencer", "silencer lol", "kaan phat gaye", "PATAAKHA", "uncle dar gaye", "mohalla jaag gaya"],
	"chalaan": ["CHALAAN lol", "warden sahab ON FIRE", "license hai bhi?", "abbu pay karein ge"],
	"chappal": ["AMMI OP", "chappal never misses", "ammi aimbot", "run shani RUN"],
	"no_hands": ["haath chhor diye?? pagal", "NO HANDS bro", "steering kis ke paas hai", "mummy dekh rahi hai?"],
	"superman": ["SUPERMAN PAI!!", "cape kahan hai", "flying munda", "how"],
	"seat_stand": ["seat pe khara hai??", "SEAT STAND bro??", "balance check", "circus join karo"],
	"selfie": ["selfie le raha hai lol", "angle acha hai", "post it on the group", "filter lagao"],
	"close": ["bal bal bacha", "uff", "heart attack", "1 inch tha"],
	"pigeons": ["kabootar bhaag gaye", "kabootar lol", "pigeon rights!!"],
	"dulha": ["dulha bhai ka reaction", "shaadi crashers", "send to the family group"],
	"over": ["OVER IT?!", "flying", "physics: ignored"],
	"pass": ["ustaad ji tusi great ho", "pindi da jakat", "VIRAL", "trending #1 in Pindi", "next video kab?"],
}

var ride
var racing := false
var show_touch := false
var clean := false            # footage: no tip banner, no key hints
var progress := {}            # level -> {views, stars}
var _shown_views := 0.0
var _chat: Array = []         # [handle, text, time]
var _seen := 0
var _pick := 0
var _last_chat := -9.0
var _panel: Control
var _touch_down := {}         # finger index -> action
var _buttons: Array = []      # touch buttons: [action, rect, label]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	size = get_viewport_rect().size     # a Control under a CanvasLayer doesn't resize itself
	if ride:
		_shown_views = move_toward(_shown_views, float(ride.views), maxf(30.0, absf(ride.views - _shown_views) * 0.12))
		_read_events()
	queue_redraw()


func new_ride(r) -> void:
	ride = r
	_shown_views = 0.0
	_chat.clear()
	_seen = 0
	_last_chat = -9.0


# ---------------------------------------------------------------- chat

func _read_events() -> void:
	for i in range(_seen, ride.events.size()):
		var ev := String(ride.events[i][1])
		var words := ev.split(" ")
		var key := words[0]
		match key:
			"bank":
				if int(words[1]) >= 400:
					_say("bank")
			"crash":
				_say("crash", true)
			"pop", "chalaan", "chappal", "pigeons", "dulha":
				_say(key)
			"trick":
				if CHAT.has(words[1]):
					_say(words[1])
			"close":
				_say("close")
			"over":
				_say("over", true)
			"finish":
				if words.size() > 1 and words[1] == "pass":
					_say("pass", true)
	_seen = ride.events.size()


func _say(kind: String, force := false) -> void:
	var lines: Array = CHAT[kind]
	_pick += 1
	if force or ride.t - _last_chat > 0.9:
		_say_line(String(lines[_pick % lines.size()]))


func _say_line(msg: String) -> void:
	_pick += 1
	_last_chat = ride.t
	_chat.append([HANDLES[(_pick * 7) % HANDLES.size()], msg, ride.t])
	if _chat.size() > 6:
		_chat.pop_front()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_buttons.clear()
	if ride == null:
		return
	if racing:
		_play_hud()
	if show_touch and racing:
		_touch_buttons()


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(at: Vector2, msg: String, px: int, col: Color, outline := 0, align := 0) -> void:
	var f := _font()
	if size.y > size.x and px < 30:
		px = int(px * 1.3)     # phones held upright: small text gets bigger
	var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pos := at
	if align == 1:
		pos.x -= w / 2.0
	elif align == 2:
		pos.x -= w
	if outline > 0:
		draw_string_outline(f, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, Color(0.08, 0.04, 0.04, col.a))
	draw_string(f, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _play_hud() -> void:
	var sz := size
	var portrait := sz.y > sz.x
	var target: int = ride.level.target
	# Views, top left: an eye, the count, and a bar to the target with star marks.
	var vx := 22.0
	var vy := 20.0
	draw_rect(Rect2(vx - 10, vy - 8, 330, 92), Color(0, 0, 0, 0.35))
	_eye(Vector2(vx + 22, vy + 30), 16.0)
	_text(Vector2(vx + 50, vy + 44), Ride.fmt(int(_shown_views)), 38, Color(1, 1, 1), 6)
	_text(Vector2(vx + 50, vy + 66), "VIEWS   target %s" % Ride.fmt(target), 15, Color(1, 0.9, 0.6), 4)
	var bar := Rect2(vx, vy + 72, 310, 8)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var f := clampf(float(_shown_views) / (target * 2.0), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(0.3, 0.9, 0.4) if _shown_views >= target else Color(1, 0.75, 0.2))
	for m in [0.5, 0.75, 1.0]:
		_star(Vector2(bar.position.x + bar.size.x * m, bar.position.y + 4), 7.0, Color(1, 0.85, 0.2) if _shown_views >= target * m * 2.0 else Color(0.5, 0.5, 0.5))
	# Abbu's patience: one chappal per crash left.
	var px := sz.x - 24.0
	_text(Vector2(px, 32), "ABBU'S PATIENCE", 14, Color(1, 1, 1), 4, 2)
	for i in Ride.PATIENCE:
		var used: bool = i >= Ride.PATIENCE - int(ride.crashes)
		_chappal_icon(Vector2(px - 18 - i * 38, 54), used)
	# The combo, top centre.
	if ride.pot > 0.0 and ride.crash_t <= 0.0:
		var cx := sz.x / 2.0
		var labels: Array = ride.chain
		var tail := labels.slice(maxi(0, labels.size() - (3 if portrait else 4)))
		var line := " + ".join(tail)
		if labels.size() > tail.size():
			line = "... + " + line
		var cy := 130.0 if portrait else 40.0
		_text(Vector2(cx, cy), line, 18, Color(1, 1, 1), 5, 1)
		var big := "%s  x%d" % [Ride.fmt(int(ride.pot)), maxi(1, int(ride.mult))]
		_text(Vector2(cx, cy + 40), big, 34, Color(1, 0.88, 0.25), 7, 1)
		var grace: float = 1.0 - float(ride.chain_idle) / Ride.CHAIN_GRACE
		if ride.chain_idle > 0.0:
			draw_rect(Rect2(cx - 80, cy + 50, 160 * grace, 5), Color(1, 0.88, 0.25, 0.9))
	# The wheelie gauge, bottom left.
	if ride.pitch > 2.0 or ride.airborne:
		_gauge(Vector2(90, sz.y - (330 if portrait and show_touch else 70)), float(ride.pitch))
	# The warden behind.
	if not ride.warden.is_empty():
		var gap: float = ride.x - float(ride.warden.x)
		if gap < 40.0 and gap > 0.0:
			var a := clampf(1.0 - gap / 40.0, 0.25, 1.0)
			var wy := sz.y * 0.45
			draw_rect(Rect2(8, wy - 26, 150, 40), Color(0.1, 0.15, 0.4, 0.75 * a))
			_text(Vector2(18, wy), "WARDEN %dm" % int(gap), 20, Color(1, 1, 1, a), 4)
	# Progress to home.
	var pw := sz.x * 0.4
	var pbx := sz.x / 2.0 - pw / 2.0
	var pby := sz.y - (20.0 if not (portrait and show_touch) else 300.0)
	draw_rect(Rect2(pbx, pby, pw, 6), Color(0, 0, 0, 0.45))
	var pf := clampf(float(ride.x) / float(ride.length), 0.0, 1.0)
	draw_rect(Rect2(pbx, pby, pw * pf, 6), Color(1, 1, 1, 0.85))
	draw_circle(Vector2(pbx + pw * pf, pby + 3), 7, Color(0.86, 0.12, 0.12))
	_text(Vector2(pbx + pw + 8, pby + 8), "GHAR", 14, Color(1, 1, 1), 4)
	# The live chat.
	_chat_box(portrait)
	# Trick keys.
	if not show_touch and not clean:
		var keys: Array = []
		for k in ride.unlocked:
			keys.append("[%s] %s" % [Ride.TRICKS[k].key, Ride.TRICKS[k].label])
		if ride.level.get("pop", false):
			keys.append("[X] PATAAKHA")
		if not keys.is_empty():
			_text(Vector2(170, sz.y - 40), "   ".join(keys), 15, Color(1, 1, 1, 0.85), 4)
	# Countdown and the tip.
	var t: float = ride.t
	if t < 0.0:
		var n := int(ceil(-t))
		_text(Vector2(sz.x / 2.0, sz.y * 0.42), str(n), 110, Color(1, 0.9, 0.3), 10, 1)
	elif t < 0.8:
		_text(Vector2(sz.x / 2.0, sz.y * 0.42), "CHALO!", 96, Color(0.4, 1, 0.5, 1.0 - t / 0.8), 10, 1)
	if t < 4.5 and not clean:
		var a := clampf(4.5 - t, 0.0, 1.0)
		var tip := touch_words(String(ride.level.tip)) if show_touch else String(ride.level.tip)
		var ty := sz.y * (0.58 if not portrait else 0.18)
		_wrap_banner(tip, Vector2(sz.x / 2.0, ty), minf(sz.x - 60.0, 900.0), a)
	if ride.result == "keys":
		_text(Vector2(sz.x / 2.0, sz.y * 0.4), "ABBU TOOK THE KEYS", 52, Color(1, 0.35, 0.3), 8, 1)


## The level tips name keyboard keys; on a phone, name the buttons instead.
static func touch_words(tip: String) -> String:
	var swaps := [["Hold SPACE to wheelie, let go to drop it", "Hold WHEELIE to lift the front, let go to drop it"],
		["press J for NO HANDS", "tap NO HANDS"], ["Press K in the air for SUPERMAN", "Tap SUPERMAN in the air"],
		["L in the air for SEAT STAND", "SEAT STAND in the air"], ["U is SELFIE", "SELFIE is new"],
		["Press X: PATAAKHA!", "Tap PATAAKHA!"]]
	for sw in swaps:
		tip = tip.replace(sw[0], sw[1])
	return tip


func _wrap_banner(msg: String, centre: Vector2, width: float, a: float) -> void:
	var f := _font()
	var px := 30 if size.y > size.x else 22
	var words := msg.split(" ")
	var lines: Array = []
	var cur := ""
	for w in words:
		var test := (cur + " " + w).strip_edges()
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width - 40.0:
			lines.append(cur)
			cur = w
		else:
			cur = test
	lines.append(cur)
	var hgt := lines.size() * px * 1.36 + 20.0
	draw_rect(Rect2(centre.x - width / 2.0, centre.y - 30, width, hgt), Color(0.1, 0.05, 0.15, 0.75 * a))
	for i in lines.size():
		_text(Vector2(centre.x, centre.y + i * px * 1.36), String(lines[i]), px, Color(1, 1, 1, a), 0, 1)


func _chat_box(portrait: bool) -> void:
	var sz := size
	var w := 300.0 if not portrait else 420.0
	var x := sz.x - w - 16.0
	var y := 90.0 if not portrait else 190.0
	if _chat.is_empty():
		return
	draw_rect(Rect2(x - 8, y - 22, w + 16, 24), Color(0.85, 0.1, 0.1, 0.85))
	_text(Vector2(x, y - 4), "LIVE   %s watching" % Ride.fmt(120 + int(ride.views / 9)), 14, Color(1, 1, 1))
	var lh := 24.0 if not portrait else 30.0
	var bg_h := _chat.size() * lh + 10.0
	draw_rect(Rect2(x - 8, y + 2, w + 16, bg_h), Color(0, 0, 0, 0.35))
	for i in _chat.size():
		var m: Array = _chat[i]
		var age: float = ride.t - float(m[2])
		var a := clampf(9.0 - age, 0.0, 1.0)
		var hy := y + 22.0 + i * lh
		_text(Vector2(x, hy), String(m[0]) + ":", 14, Color(0.55, 0.85, 1, a))
		var hw := _font().get_string_size(String(m[0]) + ": ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18 if portrait else 14).x
		_text(Vector2(x + hw, hy), String(m[1]), 14, Color(1, 1, 1, a))


func _gauge(c: Vector2, pitch: float) -> void:
	var r := 52.0
	draw_arc(c, r, PI, TAU, 32, Color(0, 0, 0, 0.5), 16.0)
	# Green between 30 and 65 degrees, red past 80.
	draw_arc(c, r, PI + deg_to_rad(Ride.SWEET.x) * 1.0, PI + deg_to_rad(Ride.SWEET.y), 16, Color(0.3, 0.9, 0.4), 12.0)
	draw_arc(c, r, PI + deg_to_rad(80.0), TAU, 8, Color(0.95, 0.25, 0.2), 12.0)
	var a := PI + deg_to_rad(clampf(pitch, 0.0, 180.0))
	draw_line(c, c + Vector2(cos(a), sin(a)) * (r + 8.0), Color(1, 1, 1), 4.0)
	draw_circle(c, 6, Color(1, 1, 1))
	_text(c + Vector2(0, 26), "WHEELIE", 14, Color(1, 1, 1), 4, 1)


func _eye(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		pts.append(c + Vector2(lerpf(-r, r, t), -sin(t * PI) * r * 0.65))
	for i in 21:
		var t := 1.0 - i / 20.0
		pts.append(c + Vector2(lerpf(-r, r, t), sin(t * PI) * r * 0.65))
	draw_colored_polygon(pts, Color(1, 1, 1))
	draw_circle(c, r * 0.42, Color(0.85, 0.12, 0.12))
	draw_circle(c, r * 0.18, Color(0.05, 0.05, 0.05))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


func _chappal_icon(c: Vector2, used: bool) -> void:
	var col := Color(0.55, 0.32, 0.14) if not used else Color(0.3, 0.3, 0.3, 0.6)
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16
		pts.append(c + Vector2(cos(a) * 15.0 * (1.0 if sin(a) < 0 else 0.85), sin(a) * 7.0).rotated(-0.4))
	draw_colored_polygon(pts, col)
	draw_line(c + Vector2(-2, -7).rotated(-0.4), c + Vector2(3, 7).rotated(-0.4), Color(0.8, 0.15, 0.1) if not used else Color(0.4, 0.4, 0.4), 3.0)
	if used:
		draw_line(c + Vector2(-14, -10), c + Vector2(14, 10), Color(0.9, 0.2, 0.2), 3.0)


# ---------------------------------------------------------------- touch

func _touch_buttons() -> void:
	var sz := size
	var portrait := sz.y > sz.x
	var r := 76.0 if portrait else 56.0
	var bottom := sz.y - r - 24.0
	var defs: Array = []
	# Left thumb: lanes and the brake. Right thumb: the wheelie (big), tricks
	# and the pataakha. On touch screens the throttle is automatic: nobody
	# can hold gas and wheelie with one thumb.
	defs.append(["up", Vector2(r + 24.0, bottom - r * 2.3), "UP"])
	defs.append(["down", Vector2(r + 24.0, bottom), "DOWN"])
	defs.append(["brake", Vector2(r * 3.4 + 24.0, bottom), "BRAKE"])
	defs.append(["wheelie", Vector2(sz.x - r * 1.25 - 24.0, bottom - r * 0.25), "WHEELIE"])
	defs.append(["menu_btn", Vector2(sz.x / 2.0, (196.0 if portrait else 112.0)), "II"])
	var extra: Array = []
	var trick_actions := {"no_hands": "trick_1", "superman": "trick_2", "seat_stand": "trick_3", "selfie": "trick_4"}
	for k in ride.unlocked:
		extra.append([trick_actions[k], String(Ride.TRICKS[k].label).replace(" ", "\n")])
	if ride.level.get("pop", false):
		extra.append(["pop", "PATAA\nKHA"])
	for i in extra.size():
		# An arc of small buttons round the wheelie button.
		var a := PI * (1.04 + 0.2 * i)
		var c := Vector2(sz.x - r * 1.25 - 24.0, bottom - r * 0.25)
		defs.append([extra[i][0], c + Vector2(cos(a), sin(a)) * r * 2.55 + Vector2(r * 0.4, 0), extra[i][1]])
	for dd in defs:
		var rad := r if not (String(dd[0]).begins_with("trick") or dd[0] == "pop") else r * 0.74
		if dd[0] == "wheelie":
			rad = r * 1.25
		elif dd[0] == "menu_btn":
			rad = r * 0.5
		var pressed := Input.is_action_pressed(String(dd[0]))
		draw_circle(dd[1], rad, Color(0, 0, 0, 0.25))
		draw_circle(dd[1], rad, Color(1, 1, 1, 0.4 if pressed else 0.16))
		draw_arc(dd[1], rad, 0, TAU, 32, Color(1, 1, 1, 0.75), 3.0)
		var lines := String(dd[2]).split("\n")
		var fs := 24 if portrait else 18
		for li in lines.size():
			_text(dd[1] + Vector2(0, fs * 0.4 + (li - (lines.size() - 1) / 2.0) * fs * 1.1), lines[li], fs, Color(1, 1, 1, 0.95), 4, 1)
		_buttons.append([String(dd[0]), dd[1], rad])


func _input(event: InputEvent) -> void:
	if not show_touch or not racing:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var act := _button_at(e.position)
			if act == "menu_btn":
				menu_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if act != "":
				_touch_down[e.index] = act
				Input.action_press(act)
		elif _touch_down.has(e.index):
			Input.action_release(String(_touch_down[e.index]))
			_touch_down.erase(e.index)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		var act := _button_at(e.position)
		if act == "menu_btn":
			act = ""
		var old := String(_touch_down.get(e.index, ""))
		if act != old:
			if old != "":
				Input.action_release(old)
			if act != "":
				Input.action_press(act)
				_touch_down[e.index] = act
			else:
				_touch_down.erase(e.index)


func _button_at(pos: Vector2) -> String:
	var local := pos
	for b in _buttons:
		if local.distance_to(b[1]) <= float(b[2]) * 1.15:
			return String(b[0])
	return ""


# ---------------------------------------------------------------- menu and results

## Lets go of every held touch button (a ride ending mid-press would
## otherwise leave, say, the wheelie held down into the next one).
func release_touches() -> void:
	for idx in _touch_down:
		Input.action_release(String(_touch_down[idx]))
	_touch_down.clear()


func hide_panels() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null


func _new_panel() -> VBoxContainer:
	size = get_viewport_rect().size     # may run before the first _process
	hide_panels()
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	_panel = holder
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.06, 0.14, 0.92)
	style.border_color = Color(1, 0.8, 0.2)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(26)
	card.add_theme_stylebox_override("panel", style)
	holder.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	return box


func _label(box: Control, msg: String, px: int, col := Color(1, 1, 1), centre := true) -> Label:
	var l := Label.new()
	if size.y > size.x and px < 40:
		px = int(px * 1.35)
	l.text = msg
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.05))
	l.add_theme_constant_override("outline_size", 6 if px >= 24 else 0)
	if centre:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = minf(size.x - 120.0, 620.0)
	box.add_child(l)
	return l


func _button(box: Control, msg: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = msg
	var big := size.y > size.x
	b.add_theme_font_size_override("font_size", 30 if big else 22)
	b.custom_minimum_size = Vector2(0, 72 if big else 48)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func show_result(title: String, lines: Array, stars: int, can_next: bool) -> void:
	var box := _new_panel()
	_label(box, "UPLOADED!" if stars > 0 else "NOT VIRAL...", 18, Color(1, 0.8, 0.3))
	_label(box, title, 40, Color(1, 0.9, 0.3) if stars > 0 else Color(1, 0.5, 0.4))
	var st := ""
	for i in 3:
		st += "* " if i < stars else "- "
	_label(box, "STARS  " + st.strip_edges(), 34, Color(1, 0.85, 0.2))
	for ln in lines:
		_label(box, String(ln), 20)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var first := _button(row, "Retry (R)", func() -> void: retry_pressed.emit())
	if can_next:
		first = _button(row, "Next ride (Enter)", func() -> void: next_pressed.emit())
	_button(row, "Menu (Esc)", func() -> void: menu_pressed.emit())
	first.grab_focus.call_deferred()


func show_menu() -> void:
	var box := _new_panel()
	_label(box, "PINDI BOY", 64, Color(1, 0.85, 0.2))
	_label(box, "Dumb stunts. Real views. Don't tell Ammi.", 20, Color(1, 1, 1))
	var grid := GridContainer.new()
	grid.columns = 2 if size.x > size.y else 1
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var first: Button = null
	for i in Levels.count():
		var lvl: Dictionary = Levels.get_level(i)
		var open := i == 0 or progress.has(i - 1) and int(progress[i - 1].stars) > 0
		var p: Dictionary = progress.get(i, {"views": 0, "stars": 0})
		var st := ""
		for s in 3:
			st += "*" if s < int(p.stars) else "-"
		var msg := "%d. %s   %s" % [i + 1, lvl.name, st] if open else "%d. LOCKED" % (i + 1)
		var b := _button(grid, msg, func() -> void: level_chosen.emit(i))
		b.add_theme_font_size_override("font_size", 26 if size.y > size.x else 18)
		b.custom_minimum_size = Vector2(330, 62 if size.y > size.x else 42)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not open
		if open:
			first = b
	var keys := "Right/D gas · Left/A brake · Up/Down change lane · SPACE wheelie (hold, feather it)\nJ K L U tricks · X pataakha · R retry · Esc menu"
	if show_touch:
		keys = "Left thumb: lanes and brake. Right thumb: hold WHEELIE and feather it.\nTricks in the air or on the back wheel. The bike speeds up by itself."
	_label(box, keys, 15, Color(0.85, 0.85, 0.95))
	if first:
		first.grab_focus.call_deferred()
