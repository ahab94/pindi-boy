#!/usr/bin/env python3
"""Synthesizes every sound in Pindi Boy from scratch: the engine putt-putt,
the pataakha silencer, rickshaw horns, cartoon stingers and a desi
bhangra-trap theme (dhol, tumbi, 808 bass), all modelled with plain maths.
No samples, no third-party audio, Python standard library only.

    python3 tools/make_audio.py

Writes 16-bit mono WAVs (Godot compresses them on import):
  audio/sfx/*.wav       comedy effects, 44.1 kHz
  audio/music/*.wav     seamless loops (ride, menu)
  audio/sfx/engine*.wav engine loops; the game bends their pitch with speed

Loops are exact to the sample: notes that run past the end wrap round to the
start. The game sets the loop points when it loads them (scripts/sound.gd).
Fixed random seeds make the output identical on every run.
"""
import array
import math
import os
import random
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "audio")
TAU = 2 * math.pi

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
              "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(note):
    """'D3', 'Bb4', 'F#2' -> frequency in Hz (A4 = 440)."""
    name, octave = note[:-1], int(note[-1])
    midi = 12 * (octave + 1) + NOTE_INDEX[name]
    return 440.0 * 2 ** ((midi - 69) / 12)


# --- Sound sources ---------------------------------------------------------

def tone(freq, dur, shape="sine", vol=0.3, attack=0.005, decay=None, release=0.03,
         glide_to=None, lowpass=None, detune=0.0, tremolo=0.0, tremolo_hz=0.0):
    """One note. `decay` = exponential fade time constant (None = sustain).
    `glide_to` slides the pitch, `detune` adds a second slightly sharp oscillator."""
    n = int(dur * SR)
    out = [0.0] * n
    p1 = p2 = 0.0
    y = 0.0
    k = 1 - math.exp(-TAU * lowpass / SR) if lowpass else None
    for i in range(n):
        t = i / SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        p1 = (p1 + f / SR) % 1.0
        s = _wave(shape, p1)
        if detune:
            p2 = (p2 + f * (1 + detune) / SR) % 1.0
            s = 0.5 * (s + _wave(shape, p2))
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay:
            env *= math.exp(-t / decay)
        if t > dur - release:
            env *= max(0.0, (dur - t) / release)
        if tremolo:
            env *= 1 - tremolo * (0.5 + 0.5 * math.sin(TAU * tremolo_hz * t))
        out[i] = s * env * vol
    return out


def _wave(shape, p):
    if shape == "sine":
        return math.sin(TAU * p)
    if shape == "saw":
        return 2 * p - 1
    if shape == "square":
        return 1.0 if p < 0.5 else -1.0
    if shape == "tri":
        return 4 * abs(p - 0.5) - 1
    raise ValueError(shape)


def noise(dur, vol=0.3, decay=0.05, lowpass=None, highpass=None, seed=1, attack=0.001,
          sweep_to=None):
    """Filtered white noise burst. `sweep_to` moves the lowpass cutoff over time."""
    rng = random.Random(seed)
    n = int(dur * SR)
    out = [0.0] * n
    lo = hi_lp = 0.0
    for i in range(n):
        t = i / SR
        s = rng.uniform(-1, 1)
        if lowpass:
            fc = lowpass if sweep_to is None else lowpass * (sweep_to / lowpass) ** (t / dur)
            lo += (1 - math.exp(-TAU * fc / SR)) * (s - lo)
            s = lo
        if highpass:
            hi_lp += (1 - math.exp(-TAU * highpass / SR)) * (s - hi_lp)
            s = s - hi_lp
        env = min(1.0, t / attack) * (math.exp(-t / decay) if decay else 1.0)
        if t > dur - 0.01:
            env *= max(0.0, (dur - t) / 0.01)
        out[i] = s * env * vol
    return out


# --- Mixing ------------------------------------------------------------------

class Track:
    """A mono buffer. With loop=True, anything that runs past the end wraps
    to the start, so the file loops seamlessly."""

    def __init__(self, seconds, loop=False):
        self.buf = array.array("f", bytes(4 * int(seconds * SR)))
        self.loop = loop

    def add(self, start, samples, gain=1.0):
        b = self.buf
        n = len(b)
        i0 = int(start * SR)
        for i, s in enumerate(samples):
            j = i0 + i
            if j >= n:
                if not self.loop:
                    break
                j %= n
            b[j] += s * gain

    def mix(self, other, gain=1.0):
        self.add(0, other.buf, gain)

    def echo(self, delay, feedback=0.35, mix=0.3):
        """Feedback delay. On a loop, run it twice so the tail wraps too."""
        b = self.buf
        n = len(b)
        d = int(delay * SR)
        wet = array.array("f", bytes(4 * n))
        for _ in range(2 if self.loop else 1):
            for i in range(n):
                j = i - d
                if j < 0 and not self.loop:
                    continue
                wet[i] = b[j % n] + feedback * wet[j % n]
        for i in range(n):
            b[i] += wet[i] * mix


def write_wav(path, samples, peak=0.89):
    """Soft-clip, normalize to `peak`, write 16-bit mono."""
    m = max(1e-9, max(abs(s) for s in samples))
    data = array.array("h", (int(32767 * peak * math.tanh(1.2 * s / m) / math.tanh(1.2)) for s in samples))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


def cat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def at(offset, samples):
    """Prefix with silence."""
    return [0.0] * int(offset * SR) + samples


def layer(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, s in enumerate(p):
            out[i] += s
    return out




# --- Desi instruments ----------------------------------------------------------

def pluck(freq, dur, vol=0.3, decay=0.996, bright=1.0, buzz=0.0, seed=1):
    """Karplus-Strong string: a burst of noise in a delay line one period
    long, averaged a little more each pass, rings like a plucked string.
    High and bright = tumbi; with `buzz` (a soft clip on the bridge) and
    lower = something sitar-ish."""
    rng = random.Random(seed)
    period = max(2, int(SR / freq))
    line = [rng.uniform(-1, 1) * bright for _ in range(period)]
    n = int(dur * SR)
    out = [0.0] * n
    j = 0
    for i in range(n):
        a = line[j]
        b = line[(j + 1) % period]
        new = decay * 0.5 * (a + b)
        if buzz:
            new = new + buzz * (new - new ** 3 * 2.0) * 0.1
        line[j] = new
        j = (j + 1) % period
        env = 1.0 if i < n - 400 else (n - i) / 400
        out[i] = a * vol * env
    return out


def harmonium(freqs, dur, vol=0.12):
    """Free reeds: each note is two slightly detuned sawtooths, softened with
    a lowpass, swelling in as the bellows push, with a slow pulse."""
    return layer(*[tone(f, dur, "saw", vol, attack=0.08, release=0.12, lowpass=1500,
                        detune=0.006, tremolo=0.12, tremolo_hz=5.0) for f in freqs])


def shehnai(freq, dur, vol=0.22, from_freq=None):
    """Double reed: a bright, nasal buzz (saw through a lowpass), a wide
    vibrato, and an optional meend (glide) in from the previous note."""
    n = int(dur * SR)
    out = [0.0] * n
    p = 0.0
    y = 0.0
    k = 1 - math.exp(-TAU * 2600 / SR)
    for i in range(n):
        t = i / SR
        f = freq
        if from_freq:
            g = min(1.0, t / 0.08)
            f = from_freq + (freq - from_freq) * (g * g * (3 - 2 * g))
        f *= 1 + 0.012 * math.sin(TAU * 6.0 * t) * min(1.0, t / 0.15)
        p = (p + f / SR) % 1.0
        s = 0.6 * (2 * p - 1) + 0.4 * (1.0 if p < 0.3 else -1.0)
        y += k * (s - y)
        env = min(1.0, t / 0.03) * min(1.0, (dur - t) / 0.04)
        out[i] = y * env * vol
    return out


def dagga(vol=0.7):
    """The dhol's big bass side: a deep boom that drops in pitch."""
    return layer(tone(78, 0.4, "sine", vol, decay=0.16, glide_to=52),
                 noise(0.06, vol * 0.35, decay=0.02, lowpass=400, seed=21))


def tilli(vol=0.35, seed=31):
    """The dhol's thin stick side: a sharp, dry crack."""
    return layer(noise(0.08, vol, decay=0.025, highpass=1800, seed=seed),
                 tone(430, 0.06, "tri", vol * 0.5, decay=0.02))


def tabla_na(freq=720, vol=0.32):
    """Dayan (right drum) 'na': a ringing tone with a few overtones."""
    return layer(tone(freq, 0.35, "sine", vol, decay=0.12),
                 tone(freq * 2.0, 0.2, "sine", vol * 0.45, decay=0.06),
                 tone(freq * 3.0, 0.12, "sine", vol * 0.25, decay=0.03),
                 noise(0.02, vol * 0.4, decay=0.006, highpass=3000, seed=int(freq)))


def tabla_ge(vol=0.5, swoop=1.6):
    """Bayan (left drum) 'ge': the heel presses the skin and the pitch swoops up."""
    return tone(88, 0.5, "sine", vol, decay=0.2, glide_to=88 * swoop)


def clap(vol=0.18, seed=41):
    return cat(noise(0.012, vol, decay=0.005, highpass=1500, seed=seed),
               noise(0.012, vol, decay=0.005, highpass=1500, seed=seed + 1),
               noise(0.08, vol, decay=0.03, highpass=1200, seed=seed + 2))


def cymbal(dur=0.9, vol=0.2, seed=51):
    return noise(dur, vol, decay=dur * 0.35, highpass=5000, seed=seed)


# --- Engine ----------------------------------------------------------------

def engine(fire_hz, seconds, body, seed):
    """A small single-cylinder four-stroke: one combustion thump per firing,
    a decaying low pulse plus a puff of exhaust noise. Firing exactly an
    integer number of times per loop keeps the loop seamless; the game bends
    the pitch with speed (Godot's pitch_scale)."""
    tr = Track(seconds, loop=True)
    n = int(round(fire_hz * seconds))
    rng = random.Random(seed)
    for k in range(n):
        t0 = k * seconds / n
        jitter = rng.uniform(0.85, 1.15)
        thump = layer(tone(body * jitter, 0.07, "sine", 0.55, decay=0.018, glide_to=body * 0.6),
                      noise(0.05, 0.35 * jitter, decay=0.012, lowpass=900, seed=seed + k))
        tr.add(t0, thump)
    # A faint valve-train tick on top.
    for k in range(n):
        tr.add(k * seconds / n + 0.5 * seconds / n, noise(0.01, 0.05, decay=0.003, highpass=3000, seed=seed + 500 + k))
    return tr.buf


# --- Effects -------------------------------------------------------------------

def pataakha():
    """The 'tuned' silencer backfiring: two cracks and a low boom with a
    rattly tail."""
    crack = lambda seed, v: layer(noise(0.25, v, decay=0.04, lowpass=5000, seed=seed),
                                  tone(70, 0.4, "sine", v * 0.9, decay=0.12, glide_to=40))
    return layer(crack(3, 0.9), at(0.11, crack(4, 1.0)), at(0.2, noise(0.4, 0.15, decay=0.12, lowpass=1500, seed=5)))


def rickshaw_horn():
    """The two-tone 'pom-pom' of a rickshaw bulb horn: a squeezed, buzzy honk."""
    def honk(f, d):
        return tone(f, d, "square", 0.25, attack=0.01, release=0.04, lowpass=1800, detune=0.02)
    return cat(honk(420, 0.14), [0.0] * int(0.05 * SR), honk(420, 0.22))


def bus_horn():
    """A pressure horn playing a jaunty little tune, as decorated buses do."""
    notes = ["E5", "G5", "A5", "G5", "E5", "D5", "E5"]
    out = []
    for nt in notes:
        out.extend(tone(hz(nt), 0.12, "saw", 0.18, attack=0.005, release=0.02, lowpass=2600, detune=0.01))
    return out


def whistle():
    """A referee whistle: a high tone warbled fast by the pea inside."""
    return layer(tone(2900, 0.5, "sine", 0.35, attack=0.01, release=0.05, tremolo=0.6, tremolo_hz=38),
                 noise(0.5, 0.06, decay=None, highpass=4000, seed=12))


def record_scratch():
    """Vinyl dragged back and forth: noise through a resonant band that
    sweeps down and up."""
    n = int(0.45 * SR)
    out = [0.0] * n
    rng = random.Random(9)
    y1 = y2 = 0.0
    for i in range(n):
        t = i / SR
        f = 900 + 2400 * abs(math.sin(TAU * 2.2 * t))
        r = 0.97
        k = 2 * r * math.cos(TAU * f / SR)
        x = rng.uniform(-1, 1)
        y = x + k * y1 - r * r * y2
        y2, y1 = y1, y
        env = min(1.0, t / 0.01) * min(1.0, (0.45 - t) / 0.05)
        out[i] = y * 0.05 * env
    return out


def sad_trombone():
    """Wah, wah, wah, waaah: four falling notes on a brassy saw with a wobble."""
    out = []
    for nt, d in [("D4", 0.32), ("C#4", 0.32), ("C4", 0.32), ("B3", 0.9)]:
        f = hz(nt)
        out.extend(tone(f, d, "saw", 0.22, attack=0.03, release=0.06, lowpass=1400,
                        tremolo=0.35 if d > 0.5 else 0.0, tremolo_hz=6.0))
    return out


def boing():
    """A cartoon spring: a sine whose pitch wobbles down."""
    n = int(0.6 * SR)
    out = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / SR
        f = 260 + 220 * math.exp(-t * 4) * math.sin(TAU * 11 * t)
        p = (p + f / SR) % 1.0
        out[i] = math.sin(TAU * p) * 0.4 * math.exp(-t * 4)
    return out


def slide_whistle(up=True):
    return tone(500 if up else 1500, 0.45, "sine", 0.3, attack=0.02, release=0.08,
                glide_to=1500 if up else 400, tremolo=0.15, tremolo_hz=7)


def kaching():
    """A coin-and-bell: views landing in the account."""
    return layer(tone(1568, 0.5, "sine", 0.25, decay=0.15), at(0.07, tone(2093, 0.6, "sine", 0.25, decay=0.2)),
                 noise(0.05, 0.2, decay=0.01, highpass=5000, seed=7))


def crowd_cheer(seed=21):
    """A small street crowd going 'oye hoye': many detuned vowel-ish tones
    rising together over a wash of noise."""
    tr = Track(1.4)
    rng = random.Random(seed)
    for k in range(10):
        f = rng.uniform(180, 420)
        tr.add(rng.uniform(0, 0.25), tone(f, 1.0, "saw", 0.05, attack=0.08, release=0.4,
                                          glide_to=f * rng.uniform(1.2, 1.5), lowpass=1200, tremolo=0.3, tremolo_hz=rng.uniform(5, 9)))
    tr.add(0, noise(1.3, 0.12, decay=0.6, lowpass=2500, highpass=300, seed=seed + 1))
    return tr.buf


def crowd_laugh(seed=31):
    """'Ha-ha-ha' from a few people: pulsed vowel tones at slightly different rates."""
    tr = Track(1.3)
    rng = random.Random(seed)
    for k in range(6):
        f = rng.uniform(200, 380)
        rate = rng.uniform(6.5, 9.0)
        start = rng.uniform(0, 0.2)
        for j in range(int(rate)):
            tr.add(start + j / rate, tone(f * (1 - j * 0.02), 0.09, "saw", 0.06, attack=0.01, release=0.04, lowpass=1500))
    tr.add(0, noise(1.1, 0.04, decay=0.5, lowpass=1800, highpass=300, seed=seed + 2))
    return tr.buf


def flutter():
    """Pigeons taking off: a burst of fast, soft wing claps."""
    tr = Track(1.0)
    rng = random.Random(41)
    for k in range(30):
        tr.add(rng.uniform(0, 0.7), noise(0.03, rng.uniform(0.1, 0.25), decay=0.01, lowpass=2500, highpass=400, seed=50 + k))
    return tr.buf


def crash():
    """Bike meets road: a thump, a metal clatter and a scrape."""
    tr = Track(1.1)
    tr.add(0, tone(70, 0.3, "sine", 0.8, decay=0.08, glide_to=40))
    tr.add(0, noise(0.12, 0.6, decay=0.04, lowpass=2000, seed=61))
    rng = random.Random(62)
    for k in range(7):
        f = rng.uniform(700, 2600)
        tr.add(0.05 + k * 0.07, layer(tone(f, 0.18, "square", 0.08, decay=0.05),
                                      tone(f * 1.47, 0.12, "sine", 0.08, decay=0.03)))
    tr.add(0.1, noise(0.9, 0.16, decay=0.4, highpass=1500, seed=63))
    return tr.buf


def thud(vol=0.6):
    return layer(tone(90, 0.2, "sine", vol, decay=0.05, glide_to=55), noise(0.06, vol * 0.4, decay=0.02, lowpass=600, seed=71))


def whoosh(seed=81):
    return noise(0.35, 0.35, decay=None, lowpass=600, sweep_to=3500, seed=seed, attack=0.12)


def splash():
    tr = Track(0.8)
    tr.add(0, noise(0.6, 0.45, decay=0.18, lowpass=3000, highpass=300, seed=91))
    rng = random.Random(92)
    for k in range(10):
        tr.add(rng.uniform(0.05, 0.5), tone(rng.uniform(900, 2000), 0.05, "sine", 0.1, decay=0.015, glide_to=rng.uniform(2000, 3000)))
    return tr.buf


def thwack():
    """A chappal landing on a target. Loud, flat, rubbery."""
    return layer(noise(0.12, 0.8, decay=0.025, lowpass=3500, seed=101), tone(180, 0.1, "sine", 0.5, decay=0.03, glide_to=90))


def shutter():
    """A phone camera: two quick clicks."""
    return cat(noise(0.02, 0.5, decay=0.005, highpass=2000, seed=111), [0.0] * int(0.06 * SR),
               noise(0.03, 0.4, decay=0.008, highpass=1500, seed=112))


def ding(note="E6"):
    return layer(tone(hz(note), 0.4, "sine", 0.3, decay=0.12), tone(hz(note) * 2.01, 0.25, "sine", 0.1, decay=0.06))


def stamp():
    """The warden's rubber stamp on the chalaan book."""
    return layer(tone(120, 0.15, "sine", 0.7, decay=0.04), noise(0.08, 0.5, decay=0.02, lowpass=1500, seed=121))


def kick_start():
    """Kick, kick, vroom: two dead kicks then the engine catches."""
    out = cat(noise(0.08, 0.3, decay=0.03, lowpass=800, seed=131), [0.0] * int(0.15 * SR),
              noise(0.08, 0.3, decay=0.03, lowpass=800, seed=132), [0.0] * int(0.1 * SR))
    tr = Track(0.6)
    for k in range(14):
        f = 18 + k * 2.5
        tr.add(k * 0.6 / 14, layer(tone(80 + k * 4, 0.05, "sine", 0.45, decay=0.015),
                                   noise(0.04, 0.25, decay=0.01, lowpass=900, seed=140 + k)))
    out.extend(tr.buf)
    return out


def fizzle():
    """Combo lost: a little descending blip."""
    return tone(700, 0.3, "square", 0.12, attack=0.005, release=0.05, glide_to=180, lowpass=2000)


def tick():
    return tone(1200, 0.08, "sine", 0.4, decay=0.02)


def go():
    return layer(tone(880, 0.4, "square", 0.18, decay=0.15, lowpass=3000), tone(1320, 0.4, "square", 0.12, decay=0.15, lowpass=3000))


def fanfare():
    """Win: a quick dhol roll and a rising tumbi flourish."""
    tr = Track(1.8)
    for k in range(8):
        tr.add(k * 0.06, tilli(0.25, seed=150 + k))
    tr.add(0.5, dagga(0.8))
    for k, nt in enumerate(["A5", "C6", "D6", "E6", "G6", "A6"]):
        tr.add(0.5 + k * 0.09, pluck(hz(nt), 0.6, 0.28, decay=0.994, seed=160 + k))
    tr.add(1.0, cymbal(0.8, 0.15))
    return tr.buf


def dhol_roll():
    tr = Track(0.9)
    for k in range(12):
        tr.add(k * 0.05, tilli(0.22, seed=170 + k))
    tr.add(0.6, dagga(0.7))
    return tr.buf


def sfx():
    d = os.path.join(OUT, "sfx")
    out = {
        "pataakha": pataakha(), "horn": rickshaw_horn(), "bus_horn": bus_horn(), "whistle": whistle(),
        "scratch": record_scratch(), "trombone": sad_trombone(), "boing": boing(),
        "slide_up": slide_whistle(True), "slide_down": slide_whistle(False), "kaching": kaching(),
        "cheer": crowd_cheer(), "laugh": crowd_laugh(), "flutter": flutter(), "crash": crash(),
        "thud": thud(), "whoosh": whoosh(), "splash": splash(), "thwack": thwack(), "shutter": shutter(),
        "ding": ding("E6"), "ding2": ding("A6"), "stamp": stamp(), "kick": kick_start(),
        "fizzle": fizzle(), "tick": tick(), "go": go(), "win": fanfare(), "dhol": dhol_roll(),
        "click": tone(1500, 0.04, "sine", 0.3, decay=0.01),
    }
    for name, samples in out.items():
        write_wav(os.path.join(d, name + ".wav"), samples)
    write_wav(os.path.join(d, "engine70.wav"), engine(24, 1.0, 95, 200), peak=0.7)
    write_wav(os.path.join(d, "engine125.wav"), engine(21, 1.0, 75, 300), peak=0.7)


# --- Music -------------------------------------------------------------------
# Pothohari flavour: a lilting 6/8 dhol (dadra feel) instead of straight
# bhangra, chimta jingles, an algoza (double flute) lead handing over to a
# shehnai, a harmonium drone, all on a Pahari-scale melody in G (Sa Re Ga Pa
# Dha, the hill mode of the Pothohar plateau). A soft 808 bass underneath
# keeps it sounding like a 2020s Short rather than a museum recording.

BPM = 104                  # dotted-quarter beats: two per 6/8 bar
EIGHTH = 60 / BPM / 3
BAR = 6 * EIGHTH
# (note, eighths) per bar: 8 bars of Pahari tune.
TUNE = [
    [("G4", 3), ("A4", 1), ("B4", 2)],
    [("D5", 3), ("B4", 1), ("A4", 2)],
    [("G4", 2), ("E4", 2), ("D4", 2)],
    [("E4", 3), ("G4", 3)],
    [("B4", 2), ("D5", 2), ("E5", 2)],
    [("D5", 3), ("B4", 1), ("A4", 1), ("G4", 1)],
    [("A4", 2), ("B4", 1), ("A4", 1), ("G4", 1), ("E4", 1)],
    [("G4", 6)],
]
ROOTS = ["G1", "D2", "E2", "C2", "G1", "D2", "C2", "G1"]


def chimta(vol=0.12, seed=1):
    """Fire tongs with jingles: a metallic clack and a short shimmer."""
    return layer(noise(0.06, vol, decay=0.012, highpass=4000, seed=seed),
                 tone(3100, 0.12, "square", vol * 0.25, decay=0.03),
                 tone(4650, 0.1, "sine", vol * 0.3, decay=0.04, tremolo=0.6, tremolo_hz=40))


def algoza(freq, dur, vol=0.16, from_freq=None):
    """Two end-blown flutes played together: a breathy, slightly detuned pair
    of near-sines with a quick vibrato, the second one droning on Sa (G)."""
    n = int(dur * SR)
    out = [0.0] * n
    p1 = p2 = 0.0
    rng = random.Random(int(freq))
    lo = 0.0
    drone = hz("G4")
    for i in range(n):
        t = i / SR
        f = freq
        if from_freq:
            g = min(1.0, t / 0.05)
            f = from_freq + (freq - from_freq) * g
        f *= 1 + 0.008 * math.sin(TAU * 5.5 * t)
        p1 = (p1 + f / SR) % 1.0
        p2 = (p2 + drone * 1.003 / SR) % 1.0
        breath = rng.uniform(-1, 1)
        lo += 0.08 * (breath - lo)
        s = (math.sin(TAU * p1) + 0.18 * math.sin(2 * TAU * p1)) + 0.35 * math.sin(TAU * p2) + 0.25 * lo
        env = min(1.0, t / 0.03) * min(1.0, (dur - t) / 0.05)
        out[i] = s * env * vol
    return out


def ride_song():
    bars = 16
    tr = Track(bars * BAR, loop=True)
    for bar in range(bars):
        t0 = bar * BAR
        # Dhol in 6/8: dagga on 1 and 4, tilli on the rest, a roll every 4th bar.
        tr.add(t0, dagga(0.6))
        tr.add(t0 + 3 * EIGHTH, dagga(0.45))
        for e in [1, 2, 4, 5]:
            tr.add(t0 + e * EIGHTH, tilli(0.22 if e in (2, 5) else 0.15, seed=bar * 8 + e))
        if bar % 4 == 3:
            for k in range(6):
                tr.add(t0 + 3 * EIGHTH + k * EIGHTH / 2, tilli(0.18, seed=900 + bar * 8 + k))
        # Chimta on the off-beats, clap on 4.
        for e in [2, 5]:
            tr.add(t0 + e * EIGHTH, chimta(0.13, seed=bar * 6 + e))
        tr.add(t0 + 3 * EIGHTH, clap(0.12, seed=bar))
        # Bass and the harmonium drone.
        root = hz(ROOTS[bar % 8])
        tr.add(t0, bass808(root, BAR * 0.95, 0.32))
        tr.add(t0, harmonium([hz("G3"), hz("D4")], BAR * 0.98, 0.045))
    # Lead: algoza takes the tune first, the shehnai answers an octave up.
    prev = None
    for half in range(2):
        t = half * 8 * BAR
        for bar_notes in TUNE:
            for note, eighths in bar_notes:
                f = hz(note)
                d = eighths * EIGHTH
                if half == 0:
                    tr.add(t, algoza(f, d + 0.02, 0.15, from_freq=prev))
                else:
                    tr.add(t, shehnai(f * 2, d + 0.03, 0.13, from_freq=prev * 2 if prev else None))
                prev = f
                t += d
    tr.echo(EIGHTH * 1.5, feedback=0.22, mix=0.12)
    return tr.buf


def bass808(freq, dur, vol=0.5, from_freq=None):
    """Sine bass with a soft clip and a quick pitch slide in, like an 808."""
    n = int(dur * SR)
    out = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / SR
        f = freq
        if from_freq:
            g = min(1.0, t / 0.06)
            f = from_freq + (freq - from_freq) * g
        p = (p + f / SR) % 1.0
        s = math.tanh(2.2 * math.sin(TAU * p))
        env = min(1.0, t / 0.005) * math.exp(-t * 0.9) * min(1.0, (dur - t) / 0.03)
        out[i] = s * env * vol
    return out


# Menu: slow and sung-poetry-like, the way a Pothohari sher is accompanied:
# harmonium chords, a lone algoza, a soft dhol every bar.
def menu_song():
    bars = 8
    slow = 1.6
    tr = Track(bars * BAR * slow, loop=True)
    for bar in range(bars):
        t0 = bar * BAR * slow
        tr.add(t0, dagga(0.4))
        tr.add(t0 + 3 * EIGHTH * slow, tilli(0.12, seed=700 + bar))
        tr.add(t0 + 5 * EIGHTH * slow, chimta(0.06, seed=800 + bar))
        tr.add(t0, harmonium([hz(ROOTS[bar].replace("1", "3").replace("2", "3")), hz("D4")], BAR * slow * 0.97, 0.06))
    t = 0.0
    prev = None
    for bar_notes in TUNE:
        for note, eighths in bar_notes:
            f = hz(note)
            d = eighths * EIGHTH * slow
            tr.add(t, algoza(f, d + 0.03, 0.14, from_freq=prev))
            prev = f
            t += d
    tr.echo(EIGHTH * 2, feedback=0.3, mix=0.2)
    return tr.buf


def music():
    d = os.path.join(OUT, "music")
    write_wav(os.path.join(d, "ride.wav"), ride_song(), peak=0.8)
    write_wav(os.path.join(d, "menu.wav"), menu_song(), peak=0.8)


def main():
    sfx()
    music()


if __name__ == "__main__":
    main()
