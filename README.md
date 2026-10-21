# Pindi Boy (working title)

**Shani is 17, lives in Pindi, and has borrowed Abbu's 70. He films everything. Every wheelie, every near-miss and every crash is content.**

A side-on stunt rider with an angled view, in the spirit of the old excite-style bike games. You get views for wheelies, air, tricks, close calls and chaos, and Abbu takes the keys after three crashes. It's built in Godot 4 and everything is drawn in code.

## Controls

| Key | Action |
|---|---|
| Right / D | Gas |
| Left / A | Brake (the rear brake also drops a wheelie) |
| Up, Down / W, S | Change lane |
| Space | Wheelie: hold to lift, let go to drop, feather it to keep the needle in the green |
| J K L U | Tricks: NO HANDS, SUPERMAN, SEAT STAND, SELFIE (in the air or on the back wheel) |
| X | PATAAKHA: the "tuned" silencer backfires |
| R / Esc / Enter | Retry / menu / next ride |

Touch screens get on-screen buttons automatically.

## How scoring works
- Stunts add views to a **combo pot** and raise the **multiplier**. Repeats are worth half as much each time and don't raise it, so variety pays.
- The combo stays alive while the front wheel is up or you're in the air. A second on two wheels **banks** it: pot × multiplier.
- A crash loses the combo. You still get +100 views, because fail videos sell.
- **Abbu's patience:** three crashes and he takes the keys.
- A wheelie squirms more the longer you hold it, so long wheelies are earned.

## The rides
| # | Ride | What's new |
|---|---|---|
| 1 | Gali Number 4 | Riding, lanes, the wheelie, potholes (wheelie over them) |
| 2 | Speed Breaker Wali Sarak | Speed breakers launch you; NO HANDS |
| 3 | Raja Bazaar Rush | Traffic, crossers, CLOSE CALLS |
| 4 | Pataakha Silencer | X backfires: pigeons scatter, goats bolt, uncles jump |
| 5 | The Plank Ramp | Plank ramps over thelas; SUPERMAN |
| 6 | Warden Sahab | A traffic warden chases you; get caught and it's a CHALAAN |
| 7 | Sawa-Sau Day | The 125: faster, bigger air; SEAT STAND; ulta rickshaws |
| 8 | Barish in Pindi | Rain and puddles that skid you |
| 9 | Shaadi Season | Baraats; a SELFIE WITH DULHA |
| 10 | Ammi Ki Dawai | Ammi throws chappals from the awnings; the warden's back |

Targets are tuned with a deliberately sloppy "rookie" bot (`tests/sim.gd --rookie`), whose views/target ratio falls from about 1.6 to 0.8 across the ten rides. An expert bot must pass every ride (`checks/autoplay.sh`).

## Look and sound
- **The look:** an oblique view where depth slides up and to the right. Wheelies read in profile, and shops, vans and buses show front, top and side.
- **The street:** procedural asphalt, paving and plaster textures, outlined and top-lit characters, soft shadows, neem trees and a tangle of wires, plus a full-screen grade, glow and vignette (`scripts/post.gdshader`).
- **Sound:** all synthesized by `python3 tools/make_audio.py`. It makes an engine putt-putt that revs with speed, the pataakha bang, the rickshaw pom-pom, the warden's whistle, a record scratch, a sad trombone, crowd cheers and a bhangra-trap ride theme.
- **The tone:** affectionate Pindi satire. There are no real brands ("the 70", "the 125") and no politics or religion. Shani is the hero, and the joke is the stunts.

## Roadmap
- [x] v0.1: 10 rides, bots, tests, synthesized audio, a fidelity pass
- [ ] The user plays it; tune the feel
- [ ] Name approval, then repo, CI exports, Pages
- [ ] Portrait Shorts and the trailer
