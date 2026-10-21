"""Edit decisions for each video. Moments are looked up in the footage's
.events files ("EVENT t=<ride s> v=<video s> name args"), so a caption or a
stinger is pinned to the frame where the crash or the jump happened.

A video: segments [(clip, start, end)] in that clip's video seconds;
captions [(start, end, text, style)] and sfx [(time, sound, volume)] in the
finished video's seconds. ev() finds a moment; at() maps a clip time into
the finished video.
"""
import os

FOOTAGE = os.path.join(os.path.dirname(__file__), "..", "..", "build", "footage")
COUNTDOWN = 3.0      # every clip opens on the 3-2-1; cut it


def events(clip):
    out = []
    path = os.path.join(FOOTAGE, clip + ".events")
    if not os.path.exists(path):
        return out
    for line in open(path):
        if not line.startswith("EVENT"):
            continue
        parts = line.split()
        v = float(parts[2][2:])
        out.append((v, " ".join(parts[3:])))
    return out


def ev(clip, prefix, nth=0):
    """Video time of the nth event starting with `prefix` in a clip."""
    hits = [v for v, text in events(clip) if text.startswith(prefix)]
    if len(hits) <= nth:
        raise KeyError(f"{clip}: no event '{prefix}' #{nth} (have {len(hits)})")
    return hits[nth]


class Edit:
    """Builds a video segment by segment so times can be written per clip."""

    def __init__(self, vid, orient="portrait"):
        self.v = {"id": vid, "orient": orient, "segments": [], "captions": [], "sfx": []}
        self.t = 0.0
        self._starts = {}

    def seg(self, clip, a, b):
        self._starts[len(self.v["segments"])] = (self.t, clip, a)
        self.v["segments"].append((clip, a, b))
        self.t += b - a
        return self

    def at(self, clip_t):
        """Map a time in the most recent segment's clip to video time."""
        t0, _, a = self._starts[len(self.v["segments"]) - 1]
        return t0 + clip_t - a

    def cap(self, t0, t1, text, style="low"):
        self.v["captions"].append((t0, t1, text, style))
        return self

    def sfx(self, t, name, vol=0.8):
        self.v["sfx"].append((t, name, vol))
        return self

    def done(self, **extra):
        self.v.update(extra)
        return self.v


VIDEOS = []


def _bus():
    c = "p-bus"
    e = Edit("short-bus").seg(c, 3.4, 14.2)
    launch, over, stand, land = ev(c, "launch"), ev(c, "over bus"), ev(c, "trick seat_stand"), ev(c, "land")
    e.cap(0.0, e.at(launch), "He jumped a BUS\non Chachu's 125", "hook")
    e.sfx(e.at(launch) - 0.1, "slide_up", 0.9)
    e.cap(e.at(over), e.at(stand), "OVER THE BUS", "big")
    e.cap(e.at(stand), e.at(land) + 0.4, "...STANDING ON THE SEAT", "big")
    e.sfx(e.at(land), "cheer", 0.9)
    e.cap(e.at(land) + 0.4, e.t, "Chachu: \"bike theek hai na?\"", "low")
    return e.done()


def _anday():
    f, w = "p-eggs-fail", "p-eggs-win"
    e = Edit("short-anday").seg(f, 4.6, 10.2)
    crash = ev(f, "crash eggs")
    e.cap(0.0, e.at(crash) - 0.1, "Attempt 1:\njump the anday wala burger", "hook")
    e.sfx(e.at(crash) + 0.6, "trombone", 0.8)
    e.cap(e.at(crash) + 0.3, e.t, "Anday wala burger 1, Shani 0", "punch")
    e.seg(w, 4.7, 10.4)
    launch, over = ev(w, "launch"), ev(w, "over eggs")
    e.cap(e.at(4.7), e.at(launch), "Attempt 2:\nwith a ramp", "hook")
    e.sfx(e.at(launch) - 0.1, "slide_up", 0.9)
    e.sfx(e.at(over), "cheer", 1.0)
    e.cap(e.at(over), e.t, "SUPERMAN OVER THE\nANDAY WALA BURGER", "big")
    return e.done()


def _loop():
    c = "p-loop"
    e = Edit("short-loop").seg(c, 3.4, 14.6)
    crash = ev(c, "crash looped")
    e.cap(0.0, 4.0, "POV: you learned wheelies\nfrom one YouTube video", "hook")
    e.cap(4.0, e.at(crash) - 0.2, "keep it in the green...", "low")
    e.sfx(e.at(crash) + 0.7, "trombone", 0.8)
    e.cap(e.at(crash) + 0.2, e.t, "Ammi ko mat batana", "punch")
    return e.done()


def _pigeons():
    c = "p-pigeons"
    e = Edit("short-pigeons").seg(c, 24.9, 31.8)
    p1, p2, p3 = ev(c, "pigeons", 0), ev(c, "pigeons", 1), ev(c, "pigeons", 2)
    e.cap(0.0, e.at(p1) - 0.05, "Pataakha silencer\nvs Pindi pigeons", "hook")
    e.sfx(e.at(p1) + 0.05, "boing", 0.6)
    e.cap(e.at(p1), e.at(p2), "Round 1", "big")
    e.cap(e.at(p2), e.at(p3), "Round 2", "big")
    e.cap(e.at(p3), e.t, "pigeon_rights_pk\nhas left the chat", "punch")
    return e.done()


def _warden():
    c = "p-warden"
    e = Edit("short-warden").seg(c, 8.4, 15.8)
    whistle, chalaan, hat = ev(c, "whistle"), ev(c, "chalaan"), ev(c, "hat")
    e.cap(0.0, e.at(whistle), "POV: you ride slow\nso the warden can't say anything", "hook")
    e.cap(e.at(whistle), e.at(chalaan), "Warden sahab:", "low")
    e.cap(e.at(chalaan) + 0.1, e.at(hat) + 1.0, "CHALAAN", "big")
    e.cap(e.at(hat) + 1.0, e.t, "...so he popped the\nsilencer at him", "punch")
    e.sfx(e.at(hat) + 0.2, "boing", 0.8)
    return e.done()


def _chappal():
    c = "p-chappal"
    e = Edit("short-chappal").seg(c, 14.2, 23.2)
    hits = [ev(c, "chappal", i) for i in range(3)]
    e.cap(0.0, e.at(hits[0]), "Ammi's chappal\nnever misses", "hook")
    for i, h in enumerate(hits):
        e.cap(e.at(h), e.at(hits[i + 1]) if i < 2 else e.at(h) + 0.9, f"AMMI {i + 1} - SHANI 0", "big")
    e.cap(e.at(hits[2]) + 0.9, e.t, "medicine delivered.\nkeys confiscated.", "punch")
    e.sfx(e.at(hits[2]) + 0.5, "trombone", 0.7)
    return e.done()


def _dulha():
    c = "p-dulha"
    e = Edit("short-dulha").seg(c, 51.3, 60.4)
    start, dulha, bank = ev(c, "trick_start selfie", 2), ev(c, "dulha"), ev(c, "bank", 5)
    e.cap(0.0, e.at(start), "Taking a selfie with the dulha\n(mid wheelie)", "hook")
    e.sfx(e.at(dulha), "cheer", 0.9)
    e.cap(e.at(dulha), e.at(dulha) + 2.2, "SELFIE WITH\nDULHA BHAI", "big")
    e.sfx(e.at(bank), "kaching", 0.9)
    e.cap(e.at(dulha) + 2.2, e.t, "now in 4 wedding videos", "punch")
    return e.done()


def _fails():
    c = "p-fails"
    e = Edit("short-fails")
    labels = [("crash rickshaw", 0, "RICKSHAW 1, SHANI 0"), ("crash wrongway", 0, "ULTA RICKSHAW 2, SHANI 0"),
              ("crash bus", 0, "BUS 3, SHANI 0")]
    for i, (name, nth, text) in enumerate(labels):
        hit = ev(c, name, nth)
        a = hit - (3.0 if name != "crash bus" else 3.6)
        e.seg(c, a, hit + 1.6)
        if i == 0:
            e.cap(0.0, e.at(hit) - 0.1, "Every way to crash\nin Pindi", "hook")
        e.cap(e.at(hit) + 0.1, e.t, text, "big")
    e.cap(e.t - 1.2, e.t, "(helmet still on the mirror)", "low")
    return e.done()


def _rain():
    c = "p-rain"
    e = Edit("short-rain")
    s1, s2, bank = ev(c, "splash", 0), ev(c, "splash", 1), ev(c, "bank", 2)
    e.seg(c, s1 - 2.0, bank + 0.8)
    e.cap(0.0, e.at(s1), "Barish in Pindi\nhits different", "hook")
    e.cap(e.at(s1) + 0.1, e.at(s1) + 1.8, "WHEELIE SPLASH", "big")
    e.seg(c, s2 - 1.2, s2 + 1.4)
    e.cap(e.at(s2) - 1.2, e.t, "Ammi: \"kapre kaun dhoyega?\"", "punch")
    return e.done()


def _gali():
    c = "p-gali"
    e = Edit("short-gali").seg(c, 4.2, 12.0)
    e.cap(0.0, 2.6, "POV: Abbu finally\ngave you the 70", "hook")
    e.cap(2.6, 5.4, "first wheelie", "low")
    e.cap(5.4, e.t, "the whole gali is watching", "low")
    bank = ev(c, "bank")
    e.seg(c, bank - 2.6, bank + 1.2)
    e.cap(e.at(bank) - 2.6, e.t, "Abbu: \"petrol kaun\ndalwaega?\"", "punch")
    return e.done()


def _trailer():
    e = Edit("trailer", "landscape")
    c = "l-ramp"
    launch = ev(c, "launch")
    e.seg(c, 4.0, 7.6)
    e.cap(0.0, 3.6, "Shani has Abbu's 70\nand a phone camera", "hook")
    e.seg(c, launch - 1.0, launch + 2.2)
    e.cap(e.at(launch), e.t, "Every stunt = VIEWS", "big")
    e.sfx(e.at(launch) - 0.1, "slide_up", 0.8)
    c = "l-eggs-win"
    over = ev(c, "over eggs")
    e.seg(c, over - 1.6, over + 1.4)
    e.cap(e.at(over), e.t, "Over the anday wala burger", "low")
    c = "l-pigeons"
    p1 = ev(c, "pigeons", 0)
    e.seg(c, p1 - 1.0, p1 + 2.0)
    e.cap(e.at(p1) - 1.0, e.t, "PATAAKHA silencer", "big")
    c = "l-warden"
    ch = ev(c, "chalaan")
    e.seg(c, ch - 2.2, ch + 1.6)
    e.cap(e.at(ch) - 2.2, e.at(ch), "The warden", "low")
    e.cap(e.at(ch), e.t, "CHALAAN", "big")
    c = "l-chappal"
    hit = ev(c, "chappal", 0)
    e.seg(c, hit - 2.4, hit + 1.4)
    e.cap(e.at(hit) - 2.4, e.t, "Ammi", "low")
    c = "l-fails"
    cr = ev(c, "crash wrongway")
    e.seg(c, cr - 2.0, cr + 1.8)
    e.cap(e.at(cr), e.t, "...and Pindi traffic", "punch")
    e.sfx(e.at(cr) + 0.8, "trombone", 0.7)
    c = "l-bus"
    ob = ev(c, "over bus")
    e.seg(c, ob - 1.8, ob + 2.4)
    e.cap(e.at(ob), e.t, "10 rides. One 125. Zero helmets.", "big")
    e.sfx(e.at(ob), "cheer", 0.9)
    return e.done(outro=3.5)


for make in (_bus, _anday, _loop, _pigeons, _warden, _chappal, _dulha, _fails, _rain, _gali, _trailer):
    try:
        VIDEOS.append(make())
    except (KeyError, OSError) as err:   # footage not recorded yet
        print("skip", make.__name__, err)
