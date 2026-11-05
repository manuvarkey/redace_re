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

## Campaign wiring (Phase 7 core, done early at the user's request)

- Generic: `ModLauncher.campaigns()` reads `res://mods/*/campaign.ini`; `Game` keeps a mod campaign's
  progress in `pilot.campaigns[id] = {won: [mission ids], score, rank}`; the original fields are never
  written by a mod campaign. Progress is by mission id, so missions added to the manifest later (101,
  103..) slot in without moving anyone's progress: the next mission is the first of the list not won.
- `bonus.html` gets `^bonuscampaigns^` (font size 4: size 5 wrapped "Der Rote Kampfflieger" out of the
  button). New placeholders `^campaigntitle^`, `^campaigncontinue^`, `^campaignstatus^`; `^rank^`,
  `^mission^`, `^score^` follow the active campaign. Links `campaign:<id>`. Entering the original
  menus (main, play, roster, goodies, bonus, Intro) leaves the mod campaign.
- Pages: `game_data/language/english/campaigns/redbaron/intro.html`, `complete.html` (the completion
  page is a placeholder until Phase 6's epilogue flow). Content kept between y 70 and 420: in a 16:9
  window the 640x480 page is filled to the width and loses about 60 px top and bottom.
- Manifest lists only the missions built so far (102, 108).
- Briefing GO BACK goes to `campaign:redbaron`.
- Found while testing: stock option tests overwrote the real `user://pilots.cfg` / `settings.cfg`;
  fixed with `Game.save_path` / `Game.settings_path` (commit db1d2f7). The Red Baron test uses the
  same scratch paths.

## Phase 3 (part): tuned Albatros folders

- `albatros_red` (the Baron) and `albatros_brenner`: design stats (highspeed 110, climb 85, highroll 80,
  highpitch 90, accel 10, firerate 25; endurance 125 / 80). Not in the design table, chosen to sit just
  above the Nieuport 17 / S.E.5a: divespeed 116, cruise 105, stall 60, lowroll 65, lowpitch 65.
- Guns: user playtest found the stand-in's fire far too slow (stock albertross 4.4 rounds/s sustained:
  firerate 10, 0.8 s on, 1.0 s off; Nieuport / S.E.5a 20.8). User chose to match the British scouts:
  firerate 25, fireon 1.0, fireoff 0.2 = 20.8 rounds/s. The design gave only firerate 25.
- Sources: `overrides/redbaron/objects/planes/<folder>/plane.ini`; `tools/build_planes.py` copies the
  stock albertross model in (paint comes later), then `godot --import`.

## Difficulty pass after the first playtest (user: "very hard")

- Comparison: original mission 1 gives the player the DH.2 (23.3 rounds/s) against stock Albatroses
  (4.4/s), about 5:1. With the sides swapped the British planes kept their strong guns (20.8..25.7/s)
  against the Baron's 20.8, about 1:1.
- Mod key `[airN] firerate / fireon / fireoff` (init.gd `configure_aircraft`, no engine change).
- Starting values: British scouts and the F.E.2d front gun at 8 rounds/s sustained in missions 1-8
  (Nieuport / S.E.5a firerate 9.6, Bristol Scout 9.33, aircodh2 8.57 with their stock bursts); planned
  12/s for missions 9-12. F.E.2d observers stay at 2.5/s.
- Mission 8: F.E.2ds retaliate off (`320` in place of `304`): they hold course, observers shoot back.
- User: raise the Baron's and Brenner's guns to the original mission 1 player's (aircodh2: firerate 25,
  1.4 s on, 0.1 s off = 23.3 rounds/s); Brenner "gets killed fast": endurance 80 -> 125 (as the Baron)
  in `albatros_brenner` and in missions 2 and 8. Design had 80 for Brenner.

## Playtest 2 (user: "winnable now"; rejoin unclear, no way to find base)

- Generic HUD hook: `World.map_markers` ({pos, icon}), drawn by `Hud._draw_map` with the other icons
  (held at the rim when far), cleared on mission load. Script API `mark_on_map(pos, icon)` / `unmark`.
  Icon `mods/redbaron/aerodrome_icon.png` (8x8 hangar, scaled 8x like the stock icons).
- Missions 2 and 8 mark the aerodrome from the start.
- Mission 2: Brenner "breaks off" when 250 from the Baron or after 10 s (was 300 / 20 s); the HUD then
  says "Brenner breaks off after the Scout! Fly close to him to call him back." Rejoin range 200 (was
  150). Message on rejoin "Brenner joins. Return to base." (user's wording). Briefing says how.
- Mission 8: "You are wounded! Land at the aerodrome." on the wound.

## Replay Missions (user request)

- Generic: manifest keys `replay` (page) and `replayall`; placeholders `^campaignreplay^` (one row per
  mission, named by its briefing's `<title>`) and `^campaignreplaylink^`; `campaigns\...` links open the
  campaign's own pages. Listed: missions won + the next, all once complete, or all with `replayall = 1`.
  A replayed mission flies outside the campaign (no progress), like the original's level selector.
- Path: Goodies → Bonus Missions → Der Rote Kampfflieger → Replay Missions. Page uses the original's
  replay art (`Menus\goodiesreplay.jpg`).
- **`replayall = 1` in `campaign.ini` while the campaign is built and tested; set it to 0 for release.**

## Playtest 3: Brenner never ran away in mission 2

- Cause: he started beside the Baron, both heading east toward the decoy at the same top speed, so he
  flew alongside; at 10 s the rejoin rule fired at once and "Brenner joins" replaced the break-off line.
- Now: the Baron and Brenner start heading north on patrol, Brenner in formation (`48` on the Baron).
  At 6 s the script sends him after the decoy (east, now starting at 7200, 7700) with the HUD line
  "Brenner breaks off after a Scout! Catch him to call him back." Brenner flies `highspeed = 118`
  (the Baron 110) so he really pulls away (about 420 away 4 s after the break with the Baron flying
  straight on). Catching him (within 200) counts once he has been 300 away, or 15 s after the break.

## Playtest 4: story steps could fire together in mission 2; return interception

- Steps now each have a HUD line and at least 4 s between them: break-off (6 s) → "Brenner is over the
  British guns! Get him out of there." when Brenner is within 300 of the Scout or the Scout is down
  (new intermediate step; the 300-away / 15 s rule is gone) → rejoin within 200.
- Not in the design: two more Nieuports (ids 3006, 3007, 8 rounds/s), hidden until the flat distance to
  the aerodrome is half what it was at the rejoin; they appear 500 ahead and 350 to the side, facing
  their targets, one attacking the Baron and one Brenner ("Enemy scouts ahead! Protect Brenner.").
- Script API: `reveal(plane, pos, then, face)` can set the heading.

## Playtest 5: home aerodrome bombed

- Stock mission 6's scenery shows the aerodrome burnt (`bighangerburn` x3, `Factory_burned`). Build key
  `[build] intact = x z r` swaps burnt / wrecked scenery for the standing model within r (bighangerburn
  -> bighanger, hangerburned -> hanger, factory_burned -> factory, tree1_burned -> tree1, housestumps
  -> house1). Missions 2 and 8: `intact = 6200 7450 700` (4 objects restored).

## Playtest 6: mission 8, shot down on the way home after the wound

- Cause: the F.E.2ds' waypoint led west over the aerodrome, so they flew home alongside the wounded
  Baron with their observers firing, and the Nieuport attacked until killed.
- Now, at the wound: the F.E.2ds turn east off the map (retaliate off, waypoint x 9600); the Nieuport
  is revealed 450 behind facing the Baron with `0x130` limit 25 s, attacks, then turns east; Brenner
  holds formation and goes for the Nieuport 12 s after the wound (6 s let him kill it before it ever
  fired). Simulated (wound 1300 from base, Baron flying straight home): the Nieuport closes to about
  140 by the aerodrome while Brenner engages it; no damage taken in that straight run.

## Playtest 7: mission 8 reworked (user's flow)

User asked for: first objective = shoot down the observers (F.E.2ds) before they leave the map; then
"Return to base"; on the way back the Baron is ambushed and takes the hit, so Brenner is beside him to
deal with it; the F.E.2d formation must be well away from the base. **Deviation from the design**, where
the wound came from an observer during the attack pass.

- F.E.2ds start about 3000 north-east of the aerodrome, fly south-west to about 1700 short of it, south
  along our lines (about 1600 out), then east to x 10000. They leave the map (150 past x 9358) at about
  38 s; their waypoint lies beyond that point, or the AI turns back at the edge when the goal is done.
  HUD counter "F.E.2d down n / 4   escaped n".
- When none is left in the air: "Return to base." (or "n got away. Return to base."), Brenner forms up.
- Halfway home (flat distance down to half of that at the return): two Nieuports (3020, 3021) appear
  250 behind and 80 above; the Baron takes a 20-point hit (never the last 10 of his endurance) and is
  wounded ("Ambush! You are hit. Land at the aerodrome."). Brenner attacks the first at once, then forms
  up; the second attacks 25 s (0x130 limit), then flies east.
- Observer hits no longer wound; the "last F.E.2d" fallback is gone.

## Playtest 8: mission 8 timing, rockets, surviving the ambush

- The Baron carries 10 rockets (`ordinancetype = 2`, `numordinance = 10`).
- F.E.2d route lengthened (all 1550+ from the aerodrome): south-west to 1700 short of it, south along
  our lines, a loop south and east, back north, then east. Simulated: they leave the map at about
  89 s, about 75 s after the Baron meets them (the user asked for 60+).
- Ambush survival (simulated with the Baron flying level for home: he was crashing into the ground
  with no input, and with the old values ambushers then shot him down): after the 20-point wound hit he
  keeps at least half his endurance and takes a quarter of each hit (mod `Aircraft.damage_scale`);
  Brenner attacks both Nieuports in turn; the second's attack limit is 20 s. Result over three runs:
  both Nieuports down about 10 s after the ambush, the Baron home with 40..46 of 125.
- Ambushers appear 250 / 310 behind, 120 either side, 80 / 110 above (they spawned on top of each
  other and collided before).

## Playtest 9: success line, minimap edge marker, debriefings

- Mission 8: "The F.E.2d flight is destroyed. Well done! Return to base." (or "3 F.E.2ds down, 1 got
  away. Return to base." / "The F.E.2ds got away. Return to base.").
- Minimap markers (generic `World.map_markers`): drawn after the aircraft icons, at full strength when
  held at the rim (other far icons are half alpha), optional `size` (Red Baron 1.5x). At half alpha on
  the rim, behind Brenner's icon, the aerodrome was hard to see.
- Debriefings (generic): `language/english/missions/<id>/debrief.html` replaces the victory message
  after a win (`^victoryurl^`); `^promotionnote^` names a promotion there, so a mod mission with a
  debriefing shows victory → debriefing instead of the promotion page; after the last mission the
  debriefing's Next Mission leads to the completion page. Original missions have none.
- Debriefing texts for missions 1-11 in `tools/missions/mNN_debrief.html` (11 is the letter from the
  design); the build tool writes them for built missions. Each closes on the next mission's setting.
  Mission 1 notes Hawker as "a brave man and a fine pilot"; nothing claimed about his burial.
