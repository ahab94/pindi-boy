#!/bin/bash
# Records autopilot gameplay for the videos into build/footage/:
#   l-<name>.mp4  landscape 1920x1080 (trailer)    p-<name>.mp4  portrait 1080x1920 (Shorts)
# Game sound effects are kept (no game music: the edit adds its own bed).
# Each clip gets a .events file (EVENT/RESULT lines from --log-events) so
# captions and stingers land on the exact jump, crash or chappal.
# Usage: bash tools/video/record_footage.sh [clip-name ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
out=build/footage
mkdir -p "$out"

# Movie Maker records at the project's window size and ignores --resolution,
# so each recording writes a temporary override.cfg with the exact size.
# --always-on-top: on macOS a covered window isn't redrawn, so the movie
# would get frozen frames.
trap 'rm -f override.cfg' EXIT
window() {  # w h
	printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" "$1" "$2" > override.cfg
}

record() {  # name level seconds extra-flags...
	local name=$1 level=$2 secs=$3; shift 3
	if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $name "* ]]; then return; fi
	local res=1920x1080
	if [[ $name == p-* ]]; then res=1080x1920; window 1080 1920; else window 1920 1080; fi
	"$GODOT" --path . --always-on-top --write-movie "$out/$name.avi" --fixed-fps 60 \
		-- --level="$level" --autopilot --clean --no-music --slowmo --fresh --exit-on-end --log-events --timeout="$secs" "$@" \
		| grep -E "^(EVENT|RESULT)" > "$out/$name.events" || true
	rm -f override.cfg
	ffmpeg -loglevel error -y -i "$out/$name.avi" -c:v libx264 -preset fast -crf 16 -pix_fmt yuv420p \
		-c:a aac -b:a 192k "$out/$name.mp4"
	rm "$out/$name.avi"
	local size; size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$out/$name.mp4")
	[ "$size" = "$res" ] || { echo "$name recorded at $size, expected $res"; exit 1; }
	local frozen; frozen=$(ffmpeg -hide_banner -i "$out/$name.mp4" -vf freezedetect=n=0.001:d=1.5 -map 0:v -f null - 2>&1 | grep -c freeze_start || true)
	echo "$name: $(grep RESULT "$out/$name.events" || echo 'no result (timeout)')  frozen-stretches=$frozen"
}

ONLY="$*"
# Note: game time (EVENT t=…) is ride time; the clip starts 3 s earlier
# (the countdown), and --slowmo stretches big moments, so specs.py reads
# frame times from the .events "@" stamps instead (see game.gd _report).
# Shorts (portrait, a little closer in).
Z=--zoom=1.12
record p-bus 6 15 --only-placed --place=70:ramp:1:p,84:bus:1:p --aim=ramp $Z
record p-eggs-fail 4 12 --only-placed --place=45:eggs:1:p --fail=eggs --no-keys $Z
record p-eggs-win 4 12 --only-placed --place=40:ramp:1:p,47:eggs:1:p --aim=ramp $Z
record p-pigeons 3 40 $Z
record p-warden 5 17 --dawdle=6 --no-keys $Z
record p-chappal 9 26 --no-dodge --no-keys $Z
record p-dulha 8 63 $Z
record p-loop 0 14 --loop-at=8 $Z
record p-fails 6 50 --fail=wrongway+bus+rickshaw+cart+eggs --no-keys $Z
record p-rain 7 40 $Z
record p-gali 0 28 $Z
# Trailer (landscape).
record l-bus 6 15 --only-placed --place=70:ramp:1:p,84:bus:1:p --aim=ramp
record l-eggs-win 4 12 --only-placed --place=40:ramp:1:p,47:eggs:1:p --aim=ramp
record l-pigeons 3 40
record l-warden 5 17 --dawdle=6 --no-keys
record l-chappal 9 26 --no-dodge --no-keys
record l-fails 6 50 --fail=wrongway+bus+rickshaw+cart+eggs --no-keys
record l-ramp 4 30
