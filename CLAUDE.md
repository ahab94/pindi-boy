# Pindi Boy: notes for Claude

A side-on, angled-view 2D stunt bike game in Godot 4.7 (GDScript). Shani, a Pindi teen, does dumb stunts on a 70 and a 125 for views. README.md holds the design and roadmap.

## Run and check
- Play: `godot --path .`
- Every change: `bash checks/verify.sh` must end with `pindi-boy: all good` (~2.5 min). It runs the smoke test, game_test.gd (each mechanic on ride.gd directly) and checks/autoplay.sh (the expert must pass every ride).
- Difficulty: `godot --headless --path . --script res://tests/sim.gd -- --rookie`. The rookie's views/target ratio should fall from about 1.6 to 0.8 ride by ride; retune `target` in levels.gd when it doesn't. Add `--verbose --level=N` (without --rookie) to print each expert crash and what was nearby.
- `checks/run.sh SECONDS <godot args>` adds a wall-clock limit (a script error makes headless Godot hang).
- Dev flags after `--`:
  - `--level=N` (0-based) skips the menu; `--autopilot` is the expert, `--rookie` the sloppy one.
  - `--exit-on-end` prints `RESULT level=… finished|keys views=… target=… stars=…`; add `--log-events` for timed EVENT lines.
  - `--trace`, and `--screenshot=x.png --wait=S` (or `--wait=1,2,3` for numbered shots).
  - `--portrait` sets a 720x1280 window; `--touch` shows the touch buttons.
  - `--slowmo` turns on recording slow motion; `--no-slowmo` turns off hit-stop too (autoplay uses it).
  - `--no-music`, `--no-post` (skips the post-process shader), `--fresh` (ignores the save), `--timeout=S`.
- Judge visuals at `--resolution 1920x1080`, not 1280x720.

## Layout
- `scripts/levels.gd`: the rides as data.
- `scripts/world.gd`: hazard KINDS and seeded street generation (hazards, buildings, poles, trees, crowd).
- `scripts/ride.gd`: all rules. Bike physics, the wheelie balance (`_step_pitch`), air, tricks, the combo (`_element`, `_bank`), crashes, traffic following and the swerving wrong-way rickshaw, crossers, pigeons, the warden and Ammi's chappals. It emits `events`.
- `scripts/autopilot.gd`: the expert and rookie bots (lane costs with path checks, wheelie feathering, trick timing).
- `scripts/view.gd`: the oblique projection `P(x, d, h)`, textures, buildings, road, trees, actor sorting, particles, popups and bubbles.
- `scripts/art.gd`: every drawing (pen frame in metres, y up; `box()` for world boxes). `ink` and `shade` turn on outlines and top-lit gradients.
- `scripts/hud.gd`: views, the combo, patience, the wheelie gauge, the live chat, results, menu and touch buttons.
- `scripts/sound.gd`: SFX pool, `EVENT_SOUNDS`, and the engine loop pitch. `audio/` comes from `python3 tools/make_audio.py`; don't hand-edit it.
- `scripts/post.gdshader`: the grade, glow and vignette.

## Conventions
- GDScript: values from untyped objects need explicit types (`var x: float = o.x`), not `:=`.
- No synthesized speech: the user rejected it in Dhoti Dash. Voices are text bubbles plus cartoon SFX. Offer the user the option to record lines.
- Slow motion only with `--slowmo` (in play it felt like a penalty); a 4-frame hit-stop on crashes.
- No real names or brands: "the 70" and "the 125", no logos, generic buses and wagons. Real Pindi place names on signs are fine.
- Comments explain why; the user is learning Godot, so briefly explain new engine concepts.
