extends Node
## Music, effects and the engine. Every file in audio/ is synthesized by
## tools/make_audio.py, so don't hand-edit the WAVs.
##
## Godot audio basics: an AudioStreamPlayer plays one stream at a time, and
## players route into named buses (Music, SFX) that mix into Master, so each
## group's volume can be set in one place. A small pool of players lets
## several effects overlap. The engine is one looping player whose
## pitch_scale follows the revs.

const NAMES := ["pataakha", "horn", "bus_horn", "whistle", "scratch", "trombone", "boing", "slide_up",
	"slide_down", "kaching", "cheer", "laugh", "flutter", "crash", "thud", "whoosh", "splash", "thwack",
	"shutter", "ding", "ding2", "stamp", "kick", "fizzle", "tick", "go", "win", "dhol", "click"]

## Ride event (the first word of a ride.gd log line) -> [[sound, dB, delay], ...]
const EVENT_SOUNDS := {
	"pop": [["pataakha", 0.0, 0.0]],
	"crash": [["crash", 0.0, 0.0], ["scratch", -2.0, 0.05], ["laugh", -6.0, 0.5]],
	"land": [["thud", -4.0, 0.0]],
	"front_down": [["thud", -8.0, 0.0]],
	"launch": [["slide_up", -6.0, 0.0], ["whoosh", -6.0, 0.0]],
	"bank": [["kaching", -3.0, 0.0]],
	"close": [["whoosh", -4.0, 0.0]],
	"pigeons": [["flutter", -2.0, 0.0]],
	"splash": [["splash", -2.0, 0.0]],
	"whistle": [["whistle", -6.0, 0.0]],
	"chalaan": [["stamp", 0.0, 0.0], ["trombone", -4.0, 0.3]],
	"chappal": [["thwack", 0.0, 0.0], ["boing", -4.0, 0.08]],
	"throw": [["slide_down", -12.0, 0.0]],
	"honk": [["horn", -6.0, 0.0]],
	"pothole": [["thud", 0.0, 0.0], ["boing", -8.0, 0.05]],
	"hat": [["boing", -2.0, 0.0]],
	"dulha": [["dhol", 0.0, 0.0], ["shutter", -2.0, 0.0]],
	"combo_lost": [["fizzle", -6.0, 0.0]],
	"respawn": [["kick", -4.0, 0.0]],
	"over": [["cheer", -3.0, 0.0]],
	"keys": [["trombone", 0.0, 0.0]],
}
const TRICK_SOUNDS := {"no_hands": "ding", "superman": "ding2", "seat_stand": "ding2", "selfie": "shutter"}

var music_on := true
var _sfx := {}
var _music_streams := {}
var _current := ""
var _music: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _engine_kind := ""
var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_bus("Music", -10.0)
	_ensure_bus("SFX", -3.0)
	for n in NAMES:
		_sfx[n] = load("res://audio/sfx/%s.wav" % n)
	for n in ["ride", "menu"]:
		_music_streams[n] = load("res://audio/music/%s.wav" % n)
		_make_loop(_music_streams[n])
	_music = _player("Music")
	_engine = _player("SFX")
	for i in 14:
		_pool.append(_player("SFX"))


func play(sound: String, volume_db := 0.0, pitch_jitter := 0.05) -> void:
	var p := _pool[0]
	for candidate in _pool:
		if not candidate.playing:
			p = candidate
			break
	p.stream = _sfx[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_event(text: String) -> void:
	var words := text.split(" ")
	var key := words[0]
	if key == "trick_start":
		return
	if key == "trick" and words.size() > 1:
		play(String(TRICK_SOUNDS.get(words[1], "ding")), -2.0)
		return
	if key == "bank" and words.size() > 1 and int(words[1]) >= 1000:
		play("cheer", -4.0)
	if key == "finish":
		play("win" if words.size() > 1 and words[1] == "pass" else "trombone")
		return
	for s in EVENT_SOUNDS.get(key, []):
		if float(s[2]) > 0.0:
			get_tree().create_timer(float(s[2]), true, false, true).timeout.connect(play.bind(String(s[0]), float(s[1])))
		else:
			play(String(s[0]), float(s[1]))


## The engine note: idle putt-putt at cruising speed, revving up with speed
## and a little extra when the front wheel is up.
func engine(kind: String, speed: float, top: float, wheelie: bool, on: bool) -> void:
	if not on:
		if _engine.playing:
			_engine.stop()
		return
	if kind != _engine_kind:
		_engine_kind = kind
		var s: AudioStreamWAV = _sfx.get("engine" + kind, null)
		if s == null:
			s = load("res://audio/sfx/engine%s.wav" % kind)
			_make_loop(s)
			_sfx["engine" + kind] = s
		_engine.stream = s
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = clampf(0.75 + speed / top * 1.1 + (0.2 if wheelie else 0.0), 0.5, 2.4)
	_engine.volume_db = -9.0 + speed / top * 4.0


func play_music(track: String) -> void:
	if track == _current:
		return
	_current = track
	_music.stop()
	if music_on and track != "":
		_music.stream = _music_streams[track]
		_music.play()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


static func _make_loop(stream: AudioStreamWAV) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))


static func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, volume_db)
