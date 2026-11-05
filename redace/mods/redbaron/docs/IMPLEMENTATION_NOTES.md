# Red Baron mod: implementation notes

Running log of deviations from `red_baron_mod_design.md` and tuning values, so the design can be
updated afterwards. Newest phase last.

## Phase 1: hooks and mission script API

Engine (generic, documented in `mods/launcher.gd`):
- `World`: `mission_step` and `mission_outcome` mod hooks; `end_message` (via `_mod_end_message`);
  `result_page(result, campaign)`; `secure_progress()` + `progress_secured` signal +
  `progress_was_secured`; `show_message(text, seconds)`. `_check_rules` now calls `_rules_result()`,
  which returns the original decision unchanged.
- `Game`: asks `world.result_page` before freeing the world; applies `progress_secured` at once
  (`_on_progress_secured`) so a later loss keeps the credit and a later win does not count twice.
  Phase 7 generalises this bookkeeping to mod campaigns.
- Export presets: exclude `*.md`, `*.blend*`, `mods/*/docs|tools|tests/*` and the test fixture
  mission 199; include `mods/*/campaign.ini` (for Phase 7).
- Gunners: `redace/mods/shared/defensive_gunners.gd` (Britain's algorithm, moved); Britain's He 111
  calls it (its tests unchanged and passing).

Mod:
- `init.gd`: optional mission keys `[mod] script`, `[environment] fogcolour / sky / ambient`,
  `[airN] gunners`. `counts_as_lost` = dead, or group 9 that left the map.
- `mission_script.gd`: script API (timers, distances, goals, reveal/hide, damage, attack, formation,
  messages, fog/sky, win/lose, result pages, end lines, secure_progress).
- `aircraft.gd`: gunners on `re8`, `handleypage`, `halberstadt` by default (`aircodh2` only with
  `gunners = 1`, as the DH.2 is a single-seater in mission 1); `damaged` signal for scripts.

Deviations / facts found:
- A mod node's `script` member clashes with `Object.script`; the init's member is `mission_script`.
- After `reveal` the plane can be in the stall state for a moment (the 0x100 appear goal keeps the nose
  at 0.196 up, as the exe); tests accept FLYING or STALL.
- Test fixture mission 199 lives in `game_data/missions/199` (World only loads missions from there).
  It has `[mod]`, so the debug `N` key cycles through it in editor runs; exports leave it out.

## Phase 2: prototype missions 2 (id 102) and 8 (id 108)

Built by `tools/build_missions.py` from `tools/missions/m02.ini`, `m08.ini` (+ `.html` briefing bodies)
with the scenery of stock mission 6 (country). Mod object ids start at 3001.

Map facts (country): world box x 4679..9358, z 4684..9368. The stock German aerodrome (where the stock
missions park enemy Albatros, hangars at x 6047, z 7414..7478) is the mod's aerodrome, centre
(6200, 7450); the British side is east (stock Allied starts at x 7400..8800).

Mission 2:
- Stand-ins: the Baron and Brenner fly `albertross` with mission overrides `highspeed = 110`,
  `endurance = 125` / `80` until Phase 3's folders exist.
- Decoy Bristol Scout trails low east over five British AA guns (x 8200..8550, z 7500..8000); two
  Nieuports appear (0x120) when Brenner is within 500 of (8000, 7700) and attack him. Reveal goals
  are followed by `type = 256` (see the plan).
- Rejoin arms when Brenner is more than 300 from the Baron or after 20 s, so the start (70 apart)
  does not count; then within 150 = formation on the Baron + "Brenner rejoins".
- Win: rejoined, and both within 300 (flat) of the aerodrome. The start is within 300 of the
  aerodrome, so the win can only come after the rejoin.
- Brenner lost: stock Group2 = 100 ("Mission Critical Object Destroyed" line).

Mission 8:
- Four `aircodh2` F.E.2d stand-ins with `gunners = 1`, `gunnerrate = 2.5` (half Britain's rate:
  at 5 rounds/s four observers took a hovering player from 125 to 15 in 10 s), retaliate on, one
  waypoint west over the German side. Design had no waypoint; added so they cross "our lines".
- Brenner: `304` before `48` (formation never ends).
- Wound: first F.E.2d hit after 30 s within 150. **Fallback (not in the design):** if all four fall
  before any qualifying hit, the wound comes with the last one, so the mission can still be finished.
  Effect: overlay (blur, grey, darker edges, slow pulse), throttle held at 0.5, guns and bombs off.
  First try at full strength made the ground unreadable; toned down (blur 0.5 + 1.5 px steps).
- After the wound the Nieuport is revealed 450 behind and 60 above the Baron, attacking him; Brenner
  attacks F.E.2ds within 800 of the Baron (re-checked every 2 s), else holds formation.
- Win: on the ground within 300 (flat) of the aerodrome. A landing elsewhere does not end the
  mission; the Baron can take off again at half throttle. Crash: stock "Plane Destroyed".
- Headless autopilot runs are not representative (the autopilot never attacks); the F.E.2ds'
  retaliation plus gunners make a passive player lose quickly. Tune after playtest.
