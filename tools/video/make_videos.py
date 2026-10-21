#!/usr/bin/env python3
"""Builds the Shorts and the trailer from recorded footage.

    bash tools/video/record_footage.sh                 # gameplay -> build/footage/
    /usr/bin/python3 tools/video/make_videos.py [id..] # -> build/videos/

Needs Pillow (captions and cards) and ffmpeg. Each video is a list of
segments cut from the footage, with the game's own sound effects kept (the
engine, the pataakha, the crashes), the ride theme underneath, captions
burned on top, comedy stingers on the big moments, and an end card.
Edit decisions live in specs.py; their times come from the footage's
.events files, so captions land on the exact crash or chappal.
Adapted from the earlier games' video tools.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOOTAGE = os.path.join(ROOT, "build", "footage")
SFX = os.path.join(ROOT, "audio", "sfx")
MUSIC = os.path.join(ROOT, "audio", "music", "ride.wav")
OUT = os.path.join(ROOT, "build", "videos")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

# Truck-art palette.
YELLOW = (255, 206, 35)
RED = (230, 40, 50)
GREEN = (40, 170, 90)
CREAM = (255, 248, 231)
INK = (30, 22, 26)


def font(size):
    return ImageFont.truetype(FONT, size)


def frame_size(orient):
    return (1080, 1920) if orient == "portrait" else (1920, 1080)


def centered(d, lines, cy, size, fill, W, stroke=10, gap=1.12):
    f = font(size)
    h = size * gap
    y = cy - h * len(lines) / 2
    for line in lines:
        w = d.textlength(line, font=f)
        d.text(((W - w) / 2, y), line, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK)
        y += h


def fit(d, lines, size, W, margin=90):
    while size > 40 and max(d.textlength(l, font=font(size)) for l in lines) > W - margin:
        size -= 4
    return size


def caption_png(path, text, style, orient):
    """A transparent full-frame PNG with the caption placed for the format.
    Portrait has empty pavement at the bottom, so most captions live there."""
    W, H = frame_size(orient)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split("\n")
    portrait = orient == "portrait"
    if style == "hook":      # the opening line: a white box over the pavement
        size = fit(d, lines, 84 if portrait else 70, W, 160)
        f = font(size)
        bw = min(W - 40, max(d.textlength(l, font=f) for l in lines) + 90)
        bh = len(lines) * size * 1.15 + 50
        cy = H * (0.86 if portrait else 0.16)
        d.rounded_rectangle([(W - bw) / 2, cy - bh / 2, (W + bw) / 2, cy + bh / 2], 36, fill=(255, 255, 255, 240),
                            outline=RED, width=8)
        centered(d, lines, cy, size, INK, W, stroke=0)
    elif style == "big":     # punchline over the shopfronts
        size = fit(d, lines, 150 if portrait else 120, W)
        centered(d, lines, H * (0.40 if portrait else 0.32), size, YELLOW, W, stroke=14)
    elif style == "punch":   # red punchline under the road
        size = fit(d, lines, 140 if portrait else 120, W)
        centered(d, lines, H * (0.86 if portrait else 0.80), size, (255, 80, 90), W, stroke=14)
    else:                    # "low": a label on a dark box
        size = fit(d, lines, 70 if portrait else 60, W, 160)
        f = font(size)
        bw = max(d.textlength(l, font=f) for l in lines) + 80
        bh = len(lines) * size * 1.15 + 40
        y0 = H * (0.86 if portrait else 0.82) - bh / 2
        d.rounded_rectangle([(W - bw) / 2, y0, (W + bw) / 2, y0 + bh], 28, fill=(20, 16, 20, 215))
        centered(d, lines, y0 + bh / 2, size, CREAM, W, stroke=0)
    img.save(path)


def card_png(path, orient):
    """End card: truck-art stripes, the title, the play line, the channel."""
    W, H = frame_size(orient)
    img = Image.new("RGB", (W, H), (34, 20, 40))
    d = ImageDraw.Draw(img)
    colors = [RED, YELLOW, GREEN, (40, 110, 220)]
    for i in range(0, H, 90):
        d.rectangle([0, i, W, i + 22], fill=colors[(i // 90) % 4])
    for i in range(0, W, 140):          # a row of painted flowers top and bottom
        for y in (70, H - 70):
            for k in range(5):
                import math
                a = k * 2 * math.pi / 5
                d.ellipse([i + 60 + math.cos(a) * 20 - 14, y + math.sin(a) * 20 - 14,
                           i + 60 + math.cos(a) * 20 + 14, y + math.sin(a) * 20 + 14], fill=colors[k % 4])
            d.ellipse([i + 48, 58, i + 72, 82], fill=YELLOW)
    d.rounded_rectangle([60, H * 0.22, W - 60, H * 0.78], 50, fill=(34, 20, 40), outline=YELLOW, width=10)
    portrait = orient == "portrait"
    title = ["PINDI", "BOY"] if portrait else ["PINDI BOY"]
    size = fit(d, title, 230 if portrait else 200, W, 200)
    cy = H * (0.40 if portrait else 0.36)
    centered(d, title, cy, size, YELLOW, W, stroke=16)
    lines = ["Dumb stunts. Real views.", "Free browser game", "coming soon"]
    centered(d, lines, H * (0.62 if portrait else 0.56), 64 if portrait else 50, CREAM, W, stroke=6)
    centered(d, ["@ahab94"], H * (0.73 if portrait else 0.71), 52 if portrait else 46, (255, 150, 160), W, stroke=4)
    img.save(path)


sys.path.insert(0, os.path.dirname(__file__))
from specs import VIDEOS  # noqa: E402


# --- Assembly --------------------------------------------------------------

def run(cmd):
    subprocess.run(cmd, check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def cut(src, start, end, path, W, H):
    """Cut [start, end] (video seconds) from a clip, keeping its sound."""
    run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{start:.3f}", "-to", f"{end:.3f}",
         "-i", os.path.join(FOOTAGE, src + ".mp4"),
         "-vf", f"scale={W}:{H},fps=60", "-af", "aresample=48000", "-ac", "2",
         "-c:v", "libx264", "-preset", "fast", "-crf", "16", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", path])


def still(png, seconds, path):
    run(["ffmpeg", "-loglevel", "error", "-y", "-loop", "1", "-t", str(seconds), "-i", png,
         "-f", "lavfi", "-t", str(seconds), "-i", "anullsrc=r=48000:cl=stereo",
         "-vf", "fps=60,format=yuv420p", "-c:v", "libx264", "-preset", "fast", "-crf", "16",
         "-c:a", "aac", "-b:a", "192k", "-shortest", path])


def loudness(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    summary = err[err.rfind("Integrated loudness"):]
    return float(summary.split("I:")[1].split()[0])


def build(v, tmp):
    W, H = frame_size(v["orient"])
    parts = []
    cut_times = []
    t = 0.0
    for i, (src, a, b) in enumerate(v["segments"]):
        parts.append(os.path.join(tmp, f"seg{i}.mp4"))
        cut(src, a, b, parts[-1], W, H)
        t += b - a
        cut_times.append(t)
    outro = v.get("outro", 2.5)
    png = os.path.join(tmp, "outro.png")
    card_png(png, v["orient"])
    parts.append(os.path.join(tmp, "outro.mp4"))
    still(png, outro, parts[-1])
    listing = os.path.join(tmp, "list.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    joined = os.path.join(tmp, "joined.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
    total = duration(joined)

    inputs, filters, last = [], [], "[0:v]"
    for i, (t0, t1, text, style) in enumerate(v["captions"]):
        cap = os.path.join(tmp, f"cap{i}.png")
        caption_png(cap, text, style, v["orient"])
        inputs += ["-loop", "1", "-t", f"{total:.2f}", "-i", cap]
        filters.append(f"{last}[{i + 1}:v]overlay=0:0:enable='between(t,{t0:.2f},{t1:.2f})'[v{i}]")
        last = f"[v{i}]"
    base = len(v["captions"]) + 1

    # Sound: the footage's own effects, the ride theme under them, stingers.
    cues = list(v.get("sfx", []))
    cues += [(c - 0.12, "whoosh", 0.35) for c in cut_times[:-1]]
    cues.append((cut_times[-1] + 0.05, "kaching", 0.8))
    audio_in = ["-stream_loop", "-1", "-i", MUSIC]
    mix = [f"[0:a]volume={v.get('game_volume', 1.0)}[g]", f"[{base}:a]volume={v.get('music_volume', 0.32)}[m]"]
    labels = ["[g]", "[m]"]
    for j, (ct, name, vol) in enumerate(cues):
        audio_in += ["-i", os.path.join(SFX, name + ".wav")]
        ms = max(0, int(ct * 1000))
        mix.append(f"[{base + 1 + j}:a]adelay={ms}|{ms},volume={vol:.2f}[s{j}]")
        labels.append(f"[s{j}]")
    mix.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,atrim=0:{total:.2f},"
               f"loudnorm=I=-14:TP=-1.5:LRA=11,afade=t=in:d=0.1,afade=t=out:st={total - 0.8:.2f}:d=0.8,"
               f"aresample=48000[a]")
    graph = ";".join(filters + mix)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, v["id"] + ".mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", joined, *inputs, *audio_in,
         "-filter_complex", graph, "-map", last, "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "60",
         "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", "-t", f"{total:.2f}", out])
    # One-pass loudnorm lands within a dB or two; measure and nudge to -14 LUFS.
    gain = -14.0 - loudness(out)
    if abs(gain) > 0.3:
        fixed = out + ".tmp.mp4"
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", out, "-c:v", "copy",
             "-af", f"volume={gain:.2f}dB,alimiter=limit=0.89", "-c:a", "aac", "-b:a", "192k", fixed])
        os.replace(fixed, out)
    print(f"{v['id']}: {total:.1f}s, {loudness(out):.1f} LUFS -> {os.path.relpath(out, ROOT)}")


def main():
    want = set(sys.argv[1:])
    for v in VIDEOS:
        if want and v["id"] not in want:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            build(v, tmp)


if __name__ == "__main__":
    main()
